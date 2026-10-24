"""Package integrity tests. Run: python3 -m unittest discover -s scripts -p 'test_build_vsix.py'."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

spec = importlib.util.spec_from_file_location('build_vsix', Path(__file__).with_name('build_vsix.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        shutil.copytree(Path(__file__).resolve().parent.parent / 'krypton-lang', self.root / 'krypton-lang')
        self.source = self.root / 'krypton-lang'

    def test_declared_assets_content_types_and_reproducible_build(self):
        (self.source / 'syntaxes' / '.git').write_text('private checkout metadata')
        output = builder.build(self.root, [])
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        with zipfile.ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            names = set(archive.namelist())
            self.assertIn('extension/snippets/krypton.json', names)
            self.assertFalse(any('.git' in name or '/test/' in name for name in names))
            manifest = json.loads(archive.read('extension/package.json'))
            for group, field in [('grammars', 'path'), ('snippets', 'path'), ('languages', 'configuration')]:
                for item in manifest['contributes'][group]:
                    self.assertIn('extension/' + item[field].removeprefix('./'), names)
            ns = {'t': 'http://schemas.openxmlformats.org/package/2006/content-types'}
            types = ET.fromstring(archive.read('[Content_Types].xml'))
            extensions = {entry.attrib['Extension'] for entry in types.findall('t:Default', ns)}
            overrides = {entry.attrib['PartName'] for entry in types.findall('t:Override', ns)}
            self.assertFalse(any(value.startswith('.') for value in extensions))
            for name in names - {'[Content_Types].xml'}:
                self.assertTrue(name.rsplit('.', 1)[-1] in extensions or '/' + name in overrides)
        builder.build(self.root, [])
        self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), digest)

    def test_escaping_contribution_is_rejected(self):
        manifest_path = self.source / 'package.json'
        package = json.loads(manifest_path.read_text())
        package['main'] = '../outside.js'
        manifest_path.write_text(json.dumps(package))
        (self.root / 'outside.js').write_text('private')
        with self.assertRaisesRegex(ValueError, 'escapes source folder'):
            builder.build(self.root, [])
        self.assertFalse((self.root / 'extensions').exists())

    def test_wrong_native_binary_cannot_replace_existing_package(self):
        output = builder.build(self.root, [])
        before = output.read_bytes()
        fake = self.root / 'wrong-kls'
        fake.write_bytes(b'not an arm64 Mach-O')
        with self.assertRaisesRegex(ValueError, 'arm64 Mach-O'):
            builder.build(self.root, ['darwin-arm64=' + str(fake)])
        self.assertEqual(output.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
