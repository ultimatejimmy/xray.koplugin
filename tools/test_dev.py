"""Regression checks for source synchronization and profile preservation."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("xray_dev", Path(__file__).with_name("dev.py"))
dev = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dev)


class SyncTests(unittest.TestCase):
    def setUp(self):
        dev.DEV.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=dev.DEV, prefix="sync-test-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        local = root / ".dev"
        profile = local / "profile"
        self.source = root / "xray.koplugin"
        self.source.mkdir()
        self.plugin = profile / "plugins/xray.koplugin"
        self.patcher = patch.multiple(dev, ROOT=root, DEV=local, PROFILE=profile,
            PLUGIN=self.plugin, MANIFEST=local / "synced-plugin-files.json")
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        (self.source / "main.lua").write_text("return {}\n")
        (self.source / "xray_config.lua").write_text("return {custom1_api_key = ''}\n")

    def test_sync_preserves_config_and_generated_data(self):
        dev.sync()
        config = self.plugin / "xray_config.lua"
        config.write_text("return {custom1_api_key = 'fake-test-only'}\n")
        cache = self.plugin / "generated.cache"
        cache.write_text("generated data")
        settings = dev.PROFILE / "settings/xray/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text(json.dumps({"language": "fr"}))
        (self.source / "main.lua").write_text("return {changed = true}\n")
        dev.sync()
        dev.sync()
        self.assertIn("fake-test-only", config.read_text())
        self.assertEqual(cache.read_text(), "generated data")
        self.assertEqual(json.loads(settings.read_text()), {"language": "fr"})
        self.assertEqual((self.plugin / "main.lua").read_text(), "return {changed = true}\n")

    def test_deleted_source_files_are_removed_without_deleting_runtime_files(self):
        dev.sync()
        (self.plugin / "xray.log").write_text("keep this log")
        (self.source / "main.lua").unlink()
        dev.sync()
        self.assertFalse((self.plugin / "main.lua").exists())
        self.assertEqual((self.plugin / "xray.log").read_text(), "keep this log")

    def test_destination_symlink_cannot_overwrite_source(self):
        dev.sync()
        (self.plugin / "main.lua").unlink()
        (self.plugin / "main.lua").symlink_to(self.source / "main.lua")
        with self.assertRaises(RuntimeError):
            dev.sync()
        self.assertEqual((self.source / "main.lua").read_text(), "return {}\n")

    def test_source_symlink_is_rejected(self):
        (self.source / "shortcut.lua").symlink_to(self.source / "main.lua")
        with self.assertRaises(RuntimeError):
            dev.sync()


if __name__ == "__main__":
    unittest.main()
