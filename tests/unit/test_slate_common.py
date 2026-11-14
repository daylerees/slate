"""scripts/slate_common.py: the helpers shared by Slate's scripts that run as you: a private
file write (0600 in a 0700 folder, whatever the umask), the prompt file's blocks, and a
download with a size cap and a SHA-256."""
import hashlib
import json
import os
import stat
import sys
import tempfile
import unittest

import slate

sys.path.insert(0, slate.path("shell", "scripts"))
import slate_common as common  # noqa: E402


class WritePrivate(unittest.TestCase):
    def test_private_under_a_loose_umask(self):
        old = os.umask(0o022)
        try:
            with tempfile.TemporaryDirectory() as d:
                path = os.path.join(d, "a", "b", "file.txt")
                common.write_private(path, "hello")
                self.assertEqual(open(path).read(), "hello")
                self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode), 0o700)
        finally:
            os.umask(old)

    def test_json_is_indented_by_one_and_private(self):
        old = os.umask(0o022)
        try:
            with tempfile.TemporaryDirectory() as d:
                path = os.path.join(d, "x.json")
                common.write_private_json(path, {"a": [1]})
                self.assertEqual(open(path).read(), json.dumps({"a": [1]}, indent=1))
                self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        finally:
            os.umask(old)


class PromptBlocks(unittest.TestCase):
    def test_picks_wanted_blocks_as_paragraphs(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "p.md")
            with open(path, "w") as fh:
                fh.write("[nova]\nOne\n two\n\n[server]\nSrv\n[shared]\nBoth\n[empty]\n\n[nova]\nLast\n")
            self.assertEqual(common.prompt_blocks(path, ("nova", "shared")), "One two\n\nBoth\n\nLast")
            self.assertEqual(common.prompt_blocks(path, ("server",)), "Srv")

    def test_missing_file_raises_oserror(self):
        with self.assertRaises(OSError):
            common.prompt_blocks("/nonexistent/prompt.md", ("nova",))

    def test_the_real_prompt_file_has_text_for_both_readers(self):
        path = slate.path("shell", "data", "assistant-prompt.md")
        self.assertTrue(common.prompt_blocks(path, ("nova", "shared")))
        self.assertTrue(common.prompt_blocks(path, ("shared", "server")))


class DownloadTo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = os.urandom(200_000)
        self.src = os.path.join(self.tmp.name, "src")
        with open(self.src, "wb") as fh:
            fh.write(self.data)
        self.dest = os.path.join(self.tmp.name, "dest")

    def test_whole_file_and_digest(self):
        seen = []
        got, digest, over = common.download_to("file://" + self.src, self.dest, 10**6, "t", 5, on_chunk=seen.append)
        self.assertEqual((got, digest, over), (len(self.data), hashlib.sha256(self.data).hexdigest(), False))
        self.assertEqual(open(self.dest, "rb").read(), self.data)
        self.assertEqual(seen[-1], len(self.data))

    def test_stops_past_the_limit(self):
        got, _digest, over = common.download_to("file://" + self.src, self.dest, 1000, "t", 5)
        self.assertTrue(over)
        self.assertGreater(got, 1000)
        self.assertLess(got, len(self.data))

    def test_on_open_gets_the_response(self):
        opened = []
        common.download_to("file://" + self.src, self.dest, 10**6, "t", 5, on_open=opened.append)
        self.assertEqual(len(opened), 1)


if __name__ == "__main__":
    unittest.main()
