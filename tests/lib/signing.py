"""A release key of the tests' own, and signatures made with it, as tools/release-assets.sh makes
Slate's (ssh-keygen -Y sign, namespace slate-release). Never Slate's real key."""
import os
import subprocess

NAMESPACE = "slate-release"


class Key:
    def __init__(self, folder, name="release"):
        os.makedirs(folder, exist_ok=True)
        self.path = os.path.join(folder, name)
        if not os.path.exists(self.path):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", name, "-f", self.path], check=True)
        with open(self.path + ".pub") as f:
            self.public = " ".join(f.read().split()[:2])

    def signers(self):
        """The allowed-signers file's text, as shell/data/release-signers has it."""
        return '# the tests\' key\nslate-release namespaces="%s" %s\n' % (NAMESPACE, self.public)

    def sign(self, data, namespace=NAMESPACE):
        """data's signature (the .sig file's bytes)."""
        r = subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", self.path, "-n", namespace],
                           input=data, capture_output=True, check=True)
        return r.stdout
