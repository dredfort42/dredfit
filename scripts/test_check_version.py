#!/usr/bin/env python3
"""Tests for check_version.py, each in a throwaway git repository.

    python3 scripts/test_check_version.py

A test builds a repository holding only what the script reads — the Xcode
project's version lines, android/gradle.properties, CHANGELOG.md and the two
scripts — commits and tags it as releases would, and runs the real script
there. The iOS expectations are the output of the script as it was before
Android had a version (develop cea8648), byte for byte: an iOS release must
keep its verdict whatever Android carries. Stdlib only, like the script.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent

# The repository's own git configuration stays out: no signing, no hooks.
GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
    "GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@example.com",
}

ANDROID_NOTICE = ("NOTICE: Android dredfit.versionName is ['2.5.0'], not "
                  "'2.5.1' — fine for an iOS-only release; "
                  "`check_version.py --android` gates an Android build")

# Printed by develop's check_version.py (cea8648) in the repositories below.
IOS_ONLY_RELEASE = """\
Expected version: 2.5.1
MARKETING_VERSION: ['2.5.1']
CURRENT_PROJECT_VERSION (build): ['27']
Previous release: v2.5.0 (build 26)

PASS: version 2.5.1 is consistent (build 27) and has a changelog entry.
"""
IOS_RELEASE_NOT_BUMPED = """\
Expected version: 2.5.1
MARKETING_VERSION: ['2.5.1']
CURRENT_PROJECT_VERSION (build): ['26']
Previous release: v2.5.0 (build 26)

FAIL: CURRENT_PROJECT_VERSION is 26, but v2.5.0 already shipped build 26; bump it above 26
FAIL: CHANGELOG.md has no '## 2.5.1' section
"""


class Repo:
    """A git repository with just the files check_version.py reads."""

    def __init__(self, root: pathlib.Path):
        self.root = root
        (root / "scripts").mkdir()
        for name in ("check_version.py", "changelog_section.py"):
            shutil.copy(SCRIPTS / name, root / "scripts" / name)
        self.git("init", "-q")

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.root, env=GIT_ENV,
                              check=True, capture_output=True, text=True,
                              timeout=60).stdout

    def commit(self, ios: str, build: int, android: str, code: str,
               changelog=("2.5.0 (Android)", "2.5.0"), separator="="):
        project = self.root / "ios" / "Dredfit.xcodeproj" / "project.pbxproj"
        project.parent.mkdir(parents=True, exist_ok=True)
        # Two targets, as the real project has more than one.
        project.write_text("".join(
            f"\t\t\t\tCURRENT_PROJECT_VERSION = {build};\n"
            f"\t\t\t\tMARKETING_VERSION = {ios};\n" for _ in range(2)),
            encoding="utf-8")
        properties = self.root / "android" / "gradle.properties"
        properties.parent.mkdir(exist_ok=True)
        properties.write_text(
            f"android.useAndroidX=true\n"
            f"dredfit.versionName{separator}{android}\n"
            f"dredfit.versionCode{separator}{code}\n", encoding="utf-8")
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n" + "".join(f"\n## {v}\n\n- notes\n"
                                      for v in changelog),
            encoding="utf-8")
        self.git("add", "-A")
        # --allow-empty: a later commit may change nothing these files hold.
        self.git("commit", "-q", "--allow-empty", "-m",
                 f"{ios} ({build}) / {android} ({code})")

    def tag(self, *names: str):
        for name in names:
            self.git("tag", name)

    def check(self, *args: str):
        run = subprocess.run(
            [sys.executable, str(self.root / "scripts" / "check_version.py"),
             *args], cwd=self.root, capture_output=True, text=True,
            timeout=60)
        return run.returncode, run.stdout


class CheckVersionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(pathlib.Path(self.tmp.name))
        # iOS and Android 2.5.0 shipped and tagged.
        self.repo.commit("2.5.0", 26, "2.5.0", "1")
        self.repo.tag("v2.5.0", "android-v2.5.0+1")

    def tearDown(self):
        self.tmp.cleanup()

    # iOS releases: develop's verdict, Android only reported.

    def test_an_ios_only_release_keeps_its_verdict(self):
        self.repo.commit("2.5.1", 27, "2.5.0", "1", ("2.5.1", "2.5.0"))
        code, out = self.repo.check("release/2.5.1")
        self.assertEqual(code, 0)
        self.assertIn(ANDROID_NOTICE + "\n", out)
        self.assertEqual(out.replace(ANDROID_NOTICE + "\n", ""),
                         IOS_ONLY_RELEASE)

    def test_a_failing_ios_release_fails_exactly_as_before(self):
        self.repo.commit("2.5.1", 26, "2.5.0", "1")
        code, out = self.repo.check("release/2.5.1")
        self.assertEqual(code, 1)
        self.assertEqual(out.replace(ANDROID_NOTICE + "\n", ""),
                         IOS_RELEASE_NOT_BUMPED)

    def test_android_in_step_adds_nothing_to_an_ios_release(self):
        self.repo.commit("2.5.1", 27, "2.5.1", "2", ("2.5.1", "2.5.0"))
        code, out = self.repo.check("release/2.5.1")
        self.assertEqual((code, out), (0, IOS_ONLY_RELEASE))

    # Android builds: one product version, a code no tag has used.

    def test_the_first_android_build_passes_with_a_notice(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        repo = Repo(pathlib.Path(tmp.name))
        repo.commit("2.5.0", 26, "2.5.0", "1")
        code, out = repo.check("--android")
        self.assertEqual(code, 0, out)
        self.assertIn("NOTICE: no android-vX.Y.Z+CODE tag yet", out)

    def test_an_android_only_fix_keeps_the_version_with_the_next_code(self):
        self.repo.commit("2.5.0", 26, "2.5.0", "2")
        code, out = self.repo.check("--android")
        self.assertEqual(code, 0, out)
        self.assertIn("Highest tagged versionCode: 1 (android-v2.5.0+1)", out)

    def test_a_code_a_tag_already_used_is_refused(self):
        self.repo.commit("2.5.0", 26, "2.5.0", "1")
        code, out = self.repo.check("--android")
        self.assertEqual(code, 1)
        self.assertIn("FAIL: dredfit.versionCode is 1, but android-v2.5.0+1 "
                      "already used 1", out)

    def test_every_tag_counts_not_only_older_versions(self):
        self.repo.commit("2.6.0", 30, "2.6.0", "5")
        self.repo.tag("android-v2.6.0+5")
        self.repo.commit("2.5.0", 26, "2.5.0", "3")
        code, out = self.repo.check("--android")
        self.assertEqual(code, 1)
        self.assertIn("but android-v2.6.0+5 already used 5", out)

    def test_the_version_name_is_the_product_version(self):
        self.repo.commit("2.5.1", 27, "2.5.0", "2")
        code, out = self.repo.check("--android")
        self.assertEqual(code, 1)
        self.assertIn("FAIL: dredfit.versionName is ['2.5.0'], expected "
                      "'2.5.1'", out)

    def test_a_code_must_be_one_positive_integer(self):
        for bad in ("0", "-1", "abc", "01", "2 ", "2\ndredfit.versionCode=3"):
            with self.subTest(code=bad):
                self.repo.commit("2.5.0", 26, "2.5.0", bad)
                code, out = self.repo.check("--android")
                self.assertEqual(code, 1, out)
                self.assertIn("expected one positive integer", out)

    def test_an_android_build_needs_its_own_changelog_section(self):
        # iOS's "## 2.5.0" shipped with v2.5.0; it says nothing of Android.
        self.repo.commit("2.5.0", 26, "2.5.0", "2", ("2.5.0",))
        code, out = self.repo.check("--android")
        self.assertEqual(code, 1)
        self.assertIn("FAIL: CHANGELOG.md has no '## 2.5.0 (Android)' section",
                      out)

    def test_gradles_spaced_property_forms_read(self):
        for separator in (" = ", ": ", " "):
            with self.subTest(separator=separator):
                self.repo.commit("2.5.0", 26, "2.5.0", "2",
                                 separator=separator)
                code, out = self.repo.check("--android")
                self.assertEqual(code, 0, out)
                self.assertIn("Android versionCode: ['2']", out)

    def test_the_tagged_build_rechecks_clean(self):
        code, out = self.repo.check("--android")
        self.assertEqual(code, 0, out)


if __name__ == "__main__":
    unittest.main()
