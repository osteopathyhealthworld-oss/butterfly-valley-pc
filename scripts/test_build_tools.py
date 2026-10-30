"""Check asset integrity and boundaries without network access or credentials."""
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import fetch_assets


class AssetFetchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.root_patch = patch.object(fetch_assets, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.data = b"asset-test-fixture"
        self.entry = {
            "source": "resources/fixture.glb",
            "destination": "game/assets/fixture.glb",
            "bytes": len(self.data),
            "sha256": hashlib.sha256(self.data).hexdigest(),
        }
        self.manifest = {"repository": "example/valley-resources",
                         "revision": "a" * 40, "files": [self.entry]}

    def test_configured_manifest_is_valid(self):
        fetch_assets.validate_manifest(self.manifest)

    def test_both_digest_formats_detect_changes(self):
        entry = copy.deepcopy(self.entry)
        entry.pop("sha256")
        entry["git_sha1"] = hashlib.sha1(
            b"blob " + str(len(self.data)).encode() + b"\0" + self.data).hexdigest()
        for candidate in (entry, self.entry):
            self.assertTrue(fetch_assets.digest_matches(self.data, candidate))
            self.assertFalse(fetch_assets.digest_matches(b"x" * len(self.data), candidate))
            self.assertFalse(fetch_assets.digest_matches(self.data + b"x", candidate))

    def test_rejects_source_and_destination_traversal(self):
        for field, value in (("source", "resources/../secret"),
                             ("destination", "game/assets/../../secret")):
            manifest = copy.deepcopy(self.manifest)
            manifest["files"][0][field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                fetch_assets.validate_manifest(manifest)

    def test_rejects_wrong_repository_revision_and_duplicate_paths(self):
        for field, value in (("repository", "https://example.org/repo"), ("revision", "main")):
            manifest = copy.deepcopy(self.manifest)
            manifest[field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                fetch_assets.validate_manifest(manifest)
        self.manifest["files"].append(copy.deepcopy(self.entry))
        with self.assertRaises(SystemExit):
            fetch_assets.validate_manifest(self.manifest)

    def test_verified_download_replaces_file_atomically(self):
        with patch.object(fetch_assets, "urlopen", return_value=io.BytesIO(self.data)):
            fetch_assets.fetch_one(self.entry, self.manifest, "test-placeholder")
        path = fetch_assets.destination(self.entry)
        self.assertEqual(path.read_bytes(), self.data)
        self.assertFalse(path.with_name(path.name + ".download").exists())

    def test_corrupt_download_preserves_existing_file(self):
        path = fetch_assets.destination(self.entry)
        path.parent.mkdir(parents=True)
        path.write_bytes(b"previous-file")
        with patch.object(fetch_assets, "urlopen", return_value=io.BytesIO(b"bad")):
            with self.assertRaisesRegex(SystemExit, "контрольная сумма"):
                fetch_assets.fetch_one(self.entry, self.manifest, "test-placeholder")
        self.assertEqual(path.read_bytes(), b"previous-file")

    def test_verified_local_assets_work_without_a_token_or_network(self):
        path = fetch_assets.destination(self.entry)
        path.parent.mkdir(parents=True)
        path.write_bytes(self.data)
        with patch.dict("os.environ", {"VALLEY_ASSETS_MANIFEST":json.dumps(self.manifest)}, clear=True), patch.object(fetch_assets, "urlopen") as request:
            fetch_assets.main()
        request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
