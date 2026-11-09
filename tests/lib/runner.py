#!/usr/bin/env python3
"""Runs Slate's test tiers and reports the results the same way for every check.

Normally started by tests/run (which sets up the container); runs directly too:
    python3 tests/lib/runner.py [--tier static,unit] [-q|-v] [--json] [--filter text]

Each test file is tests/<tier>/test_*.py (Python unittest). A subTest counts as its own
check, so "every QML file lints" is one check per file. Output:
    default   a line per tier, every failure, and a summary
    -q        only failures and the summary line ("PASS 412/412" or "FAIL 3/412")
    -v        every check, passes included
    --json    one JSON object per failure, then {"summary": …}
Exit code 0 only when everything that ran passed (skips are reported, and don't fail).
"""
import argparse
import importlib.util
import io
import json
import os
import sys
import time
import traceback
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slate  # noqa: E402

TIERS = ["static", "unit", "live", "visual"]


def short_name(test, subtest=None):
    """'static/qml › lint › Bar.qml' from a unittest id and subtest params."""
    parts = test.id().split(".")      # tests.<tier>.test_<file>.<Class>.test_<method>
    tier, file, method = parts[1], parts[2], parts[-1]
    name = f"{tier}/{file.removeprefix('test_')} › {method.removeprefix('test_')}"
    if subtest is not None:
        params = getattr(subtest, "params", {}) or {}
        label = ", ".join(str(v) for v in params.values()) or (subtest._message if isinstance(subtest._message, str) else "")
        if label:
            name += f" › {label}"
    return name


def reason(err):
    """The one-line reason for a failure: the assertion's message, or the exception."""
    etype, value, tb = err
    text = str(value).strip()
    if etype is AssertionError or issubclass(etype, AssertionError):
        # unittest's long diffs: keep the first line, the full text goes to the log
        first = text.splitlines()[0] if text else "assertion failed"
        return first, text
    where = traceback.extract_tb(tb)[-1] if tb else None
    loc = f" ({os.path.relpath(where.filename, slate.ROOT)}:{where.lineno})" if where else ""
    full = "".join(traceback.format_exception(etype, value, tb))
    return f"{etype.__name__}: {text.splitlines()[0] if text else ''}{loc}", full


class Result(unittest.TestResult):
    def __init__(self, mode, out):
        super().__init__()
        self.mode = mode            # quiet, normal, verbose, json
        self.out = out
        self.passed = 0
        self.failed = []            # (name, one-line reason, log path)
        self.skipped_names = []
        self._had_sub = set()
        self._t0 = {}

    def _fail(self, name, err):
        line, full = reason(err)
        logpath = None
        if "\n" in full.strip():
            d = os.path.join(slate.OUT, "logs")
            os.makedirs(d, exist_ok=True)
            logpath = os.path.join(d, name.replace(" › ", "--").replace("/", "_").replace(" ", "_")[:150] + ".txt")
            with open(logpath, "w", encoding="utf-8") as f:
                f.write(full)
            logpath = os.path.relpath(logpath, os.getcwd())
        self.failed.append((name, line, logpath))
        if self.mode == "json":
            self.out.write(json.dumps({"test": name, "reason": line, "log": logpath}) + "\n")
        else:
            self.out.write(f"FAIL {name}: {line}" + (f"  [{logpath}]" if logpath and logpath not in line else "") + "\n")
        self.out.flush()

    def _pass(self, name):
        self.passed += 1
        if self.mode == "verbose":
            self.out.write(f"  ok {name}\n")

    def startTest(self, test):
        super().startTest(test)
        self._t0[test.id()] = time.monotonic()

    def addSubTest(self, test, subtest, err):
        super().addSubTest(test, subtest, err)
        self._had_sub.add(test.id())
        name = short_name(test, subtest)
        if err is None:
            self._pass(name)
        elif issubclass(err[0], unittest.SkipTest):
            self.skipped_names.append((name, str(err[1])))
        else:
            self._fail(name, err)

    def addSuccess(self, test):
        super().addSuccess(test)
        if test.id() not in self._had_sub:
            self._pass(short_name(test))

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self._fail(short_name(test), err)

    def addError(self, test, err):
        super().addError(test, err)
        # errors in setUpClass/module come through with a _ErrorHolder
        name = short_name(test) if hasattr(test, "_testMethodName") else str(test)
        self._fail(name, err)

    def addSkip(self, test, why):
        super().addSkip(test, why)
        name = short_name(test) if hasattr(test, "_testMethodName") else str(test)
        self.skipped_names.append((name, why))
        if self.mode == "verbose":
            self.out.write(f"skip {name}: {why}\n")

    def addExpectedFailure(self, test, err):
        super().addExpectedFailure(test, err)
        self._pass(short_name(test))

    def addUnexpectedSuccess(self, test):
        super().addUnexpectedSuccess(test)
        self._fail(short_name(test), (AssertionError, AssertionError("passed, but was expected to fail"), None))

    @property
    def total(self):
        return self.passed + len(self.failed)


def load_tier(tier):
    """A suite of every tests/<tier>/test_*.py."""
    d = os.path.join(slate.TESTS, tier)
    suite = unittest.TestSuite()
    if not os.path.isdir(d):
        return suite
    sys.path.insert(0, d)
    for f in sorted(os.listdir(d)):
        if not (f.startswith("test_") and f.endswith(".py")):
            continue
        modname = f"tests.{tier}.{f[:-3]}"
        spec = importlib.util.spec_from_file_location(modname, os.path.join(d, f))
        mod = importlib.util.module_from_spec(spec)
        sys.modules[modname] = mod
        try:
            spec.loader.exec_module(mod)
        except Exception:  # a broken test file is a failure, not a crash of the whole run
            err = sys.exc_info()

            class Broken(unittest.TestCase):
                def runTest(self, err=err):
                    raise err[1].with_traceback(err[2])
            Broken.__module__ = modname
            Broken.__qualname__ = Broken.__name__ = "load"
            suite.addTest(Broken())
            continue
        suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(mod))
    return suite


def flatten(suite):
    for t in suite:
        if isinstance(t, unittest.TestSuite):
            yield from flatten(t)
        else:
            yield t


def filtered(suite, text):
    """Only the tests whose name contains `text` (subtests are filtered by the tests themselves
    through SLATE_TEST_FILTER)."""
    keep = unittest.TestSuite()
    for t in flatten(suite):
        name = short_name(t) if hasattr(t, "_testMethodName") else t.id()
        if getattr(t, "filters_itself", False) or text.lower() in name.lower() or text.lower() in t.id().lower():
            keep.addTest(t)
    return keep


def main(argv=None):
    ap = argparse.ArgumentParser(description="Run Slate's tests")
    ap.add_argument("--tier", default="static,unit", help="static, unit, live, visual, all (comma list)")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--filter", default="")
    ap.add_argument("--label", default="", help="added to the summary line, e.g. [latest deps]")
    a = ap.parse_args(argv)

    tiers = TIERS if a.tier == "all" else [t.strip() for t in a.tier.split(",") if t.strip()]
    bad = [t for t in tiers if t not in TIERS]
    if bad:
        ap.error(f"unknown tier: {', '.join(bad)}")
    mode = "json" if a.json else "quiet" if a.quiet else "verbose" if a.verbose else "normal"
    os.makedirs(slate.OUT, exist_ok=True)
    os.environ["SLATE_TEST_FILTER"] = a.filter
    out = sys.stdout
    result = Result(mode, out)
    t0 = time.monotonic()
    for tier in tiers:
        suite = load_tier(tier)
        if a.filter:
            suite = filtered(suite, a.filter)
        n_before, f_before = result.total, len(result.failed)
        tt = time.monotonic()
        # Keep tests' own stray output out of the report
        real_out, real_err = sys.stdout, sys.stderr
        sys.stdout = sys.stderr = io.StringIO()
        try:
            suite.run(result)
        finally:
            sys.stdout, sys.stderr = real_out, real_err
        if mode == "normal":
            ran = result.total - n_before
            failed = len(result.failed) - f_before
            out.write(f"{tier:7} {ran - failed}/{ran} passed ({time.monotonic() - tt:.1f}s)\n")

    took = time.monotonic() - t0
    label = f" {a.label}" if a.label else ""
    skips = len(result.skipped_names)
    if mode == "json":
        out.write(json.dumps({"summary": {"passed": result.passed, "failed": len(result.failed),
                                          "total": result.total, "skipped": skips, "seconds": round(took, 1),
                                          "tiers": tiers, "label": a.label}}) + "\n")
    else:
        if skips and mode != "quiet":
            for name, why in result.skipped_names[:20]:
                out.write(f"skip {name}: {why}\n")
        verdict = "FAIL" if result.failed else "PASS"
        extra = f", {skips} skipped" if skips else ""
        out.write(f"{verdict} {result.passed}/{result.total}{label} ({took:.0f}s{extra})\n")
    return 1 if result.failed or result.total == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
