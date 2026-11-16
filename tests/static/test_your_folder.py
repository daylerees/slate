"""Your own Slate files (settings.json, hypr/, user/) are always read from your own Slate folder,
${XDG_CONFIG_HOME:-$HOME/.config}/slate, wherever Slate's code is: next to it for an install of
your own, apart from it when Slate is installed once for everyone. The rule is written in each
language that needs it; every copy is checked here, and nothing reads your files from next to
the code."""
import re

import slate
from slate import Case

# Each file that works out your folder, and the rule as it's written there
RULE = {
    "shell/Config.qml": ['Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"',
                         'readonly property string userDir: configHome + "/slate"'],
    "shell/bin/slate": ['SLATE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/slate"'],
    "shell/bin/slate-factory-reset": ['SLATE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/slate"'],
    "shell/scripts/user-files.sh": ['dir="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/slate}"'],
    "shell/scripts/screenshot.sh": ['"${XDG_CONFIG_HOME:-$HOME/.config}/slate/settings.json"'],
    "shell/session/slate-session": ['"${XDG_CONFIG_HOME:-$HOME/.config}/slate"'],
    "shell/session/hypr/hyprland.lua": ['local yourSlate = (env("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/slate"',
                                        'local userDir = yourSlate .. "/hypr"'],
    "shell/scripts/apply-theme.py": ['os.path.join(CFG, "slate", "settings.json")'],
    "shell/scripts/slate_theme.py": ['CFG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")'],
    "shell/UserFiles.qml": ['Config.userDir + "/hypr"', 'Config.userDir + "/user/shell.qml"'],
    "shell/bin/slate-logs": ['SLATE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/slate"'],
    "shell/bin/slate-greeter-sync": ['YOURS="${XDG_CONFIG_HOME:-$HOME/.config}/slate"', 'look "$YOURS/settings.json" | write settings.json'],
}

# Where Slate's code is: your own install (or a link) first, then the copy for everyone, in the
# same order everywhere that looks
CODE_ORDER = {
    "shell/session/slate-session": ['"${XDG_CONFIG_HOME:-$HOME/.config}/slate" $SHARED', 'SHARED="/usr/local/share/slate /usr/share/slate"'],
    "shell/bin/slate-greeter-install": ['for d in "$HOMEDIR/.config/slate" /usr/local/share/slate /usr/share/slate; do'],
    "install.sh": ['if [ -f "$DEST/session/hypr/hyprland.lua" ]; then echo "$DEST"; else echo "$CODE"; fi', 'CODE=/usr/local/share/slate '],
}

ALLOWED = set()

# Ways of reaching your files through the code's own folder
NEXT_TO_CODE = [
    r'\$SLATE_DIR/(settings\.json|hypr\b|user/)',
    r'\$here/\.\./settings\.json',
    r'shellPath\("(settings\.json|hypr|user/)',
    r'os\.path\.join\([^)]*(__file__|SLATE_DIR|SHELL_DIR|HERE)[^)]*"settings\.json"',
]


class YourFolder(Case):
    def test_every_copy_of_the_rule(self):
        for path, lines in RULE.items():
            src = slate.read(*path.split("/"))
            for line in lines:
                with self.subTest(path, line=line):
                    self.assertIn(line, src, f"{path} works out your Slate folder differently")

    def test_every_copy_of_where_the_code_is(self):
        for path, lines in CODE_ORDER.items():
            src = slate.read(*path.split("/"))
            for line in lines:
                with self.subTest(path, line=line):
                    self.assertIn(line, src, f"{path} looks for Slate's code differently")

    def test_nothing_reads_your_files_next_to_the_code(self):
        files = slate.run(["git", "-C", slate.path(), "ls-files", "shell"])[1].split()
        for rel in files:
            if not rel.endswith((".qml", ".sh", ".py", ".lua")) and "/bin/" not in rel and "session/slate-session" not in rel:
                continue
            # (the login screen reads its copy of your settings from next to its code, on
            # purpose: slate-greeter-install puts it there)
            if rel.startswith("shell/greeter/") or rel.startswith("shell/bin/slate-greeter"):
                continue
            try:
                src = slate.read(*rel.split("/"))
            except (UnicodeDecodeError, IsADirectoryError):
                continue
            for n, line in enumerate(src.splitlines(), 1):
                if line.lstrip().startswith(("#", "//", "--")):
                    continue
                if any(rel == f and frag in line for f, frag in ALLOWED):
                    continue
                for pat in NEXT_TO_CODE:
                    with self.subTest(rel, line=n):
                        self.assertIsNone(re.search(pat, line), f"{rel}:{n} reads your files next to Slate's code: {line.strip()}")

    def test_config_reads_settings_from_your_folder(self):
        src = slate.read("shell", "Config.qml")
        # (the login screen's own: the chosen person's look, or the shared one; everyone else's: theirs)
        self.assertRegex(src, r'path: root\.isLoginScreen \? \(root\.loginLook !== "" \? root\.loginLook \+ "/settings\.json"[\s\S]{0,160}?\n\s*: root\.userDir \+ "/settings\.json"')
