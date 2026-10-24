#!/usr/bin/env python3
"""Build the extension using only Python's standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import xml.etree.ElementTree as ET
import zipfile


def build(root, bundles):
    source = root / 'krypton-lang'
    package = json.loads((source / 'package.json').read_text())
    files = {'package.json', package['main'], 'README.md', 'LICENSE'}
    contributions = package['contributes']
    for group, key in [('languages', 'configuration'), ('grammars', 'path'), ('snippets', 'path')]:
        files.update(item[key] for item in contributions.get(group, []) if key in item)
    payload = {}
    for name in files:
        target = (source / name).resolve()
        if not target.is_relative_to(source.resolve()):
            raise ValueError('Extension contribution escapes source folder: ' + name)
        payload['extension/' + target.relative_to(source.resolve()).as_posix()] = (target.read_bytes(), 0o644)
    servers = {}
    for spec in bundles:
        platform, binary = spec.split('=', 1)
        if platform != 'darwin-arm64':
            raise ValueError('Only verified darwin-arm64 bundling is currently supported')
        data = Path(binary).read_bytes()
        if len(data) < 8 or struct.unpack('<II', data[:8]) != (0xfeedfacf, 0x100000c):
            raise ValueError('Expected an arm64 Mach-O kls binary')
        name = 'server/' + platform + '/kls'
        payload['extension/' + name] = (data, 0o755)
        servers[platform] = {'path': name, 'sha256': hashlib.sha256(data).hexdigest()}
    if servers:
        payload['extension/server/manifest.json'] = ((json.dumps(servers, indent=2) + '\n').encode(), 0o644)

    namespace = 'http://schemas.microsoft.com/developer/vsx-schema/2011'
    ET.register_namespace('', namespace)
    manifest = ET.Element('{' + namespace + '}PackageManifest', Version='2.0.0')
    metadata = ET.SubElement(manifest, 'Metadata')
    ET.SubElement(metadata, 'Identity', Language='en-US', Id=package['name'],
                  Version=package['version'], Publisher=package['publisher'])
    ET.SubElement(metadata, 'DisplayName').text = package['displayName']
    ET.SubElement(metadata, 'Description').text = package['description']
    ET.SubElement(metadata, 'Categories').text = ','.join(package['categories'])
    properties = ET.SubElement(metadata, 'Properties')
    ET.SubElement(properties, 'Property', Id='Microsoft.VisualStudio.Code.Engine', Value=package['engines']['vscode'])
    installation = ET.SubElement(manifest, 'Installation')
    ET.SubElement(installation, 'InstallationTarget', Id='Microsoft.VisualStudio.Code')
    ET.SubElement(manifest, 'Dependencies')
    assets = ET.SubElement(manifest, 'Assets')
    for kind, name in [('Manifest', 'package.json'), ('Details', 'README.md'), ('License', 'LICENSE')]:
        ET.SubElement(assets, 'Asset', Type='Microsoft.VisualStudio.Code.' + kind,
                      Path='extension/' + name, Addressable='true')
    payload['extension.vsixmanifest'] = (ET.tostring(manifest, encoding='utf-8', xml_declaration=True), 0o644)

    types = ET.Element('Types', xmlns='http://schemas.openxmlformats.org/package/2006/content-types')
    mime_types = {'json': 'application/json', 'js': 'application/javascript', 'md': 'text/markdown', 'vsixmanifest': 'text/xml'}
    for extension, mime in mime_types.items():
        ET.SubElement(types, 'Default', Extension=extension, ContentType=mime)
    for name in sorted(payload):
        if name.rsplit('.', 1)[-1] not in mime_types:
            ET.SubElement(types, 'Override', PartName='/' + name, ContentType='application/octet-stream')
    payload['[Content_Types].xml'] = (ET.tostring(types, encoding='utf-8', xml_declaration=True), 0o644)

    output = root / 'extensions' / ('krypton-language-' + package['version'] + '.vsix')
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=output.parent, suffix='.tmp')
    os.close(handle)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, (data, mode) in sorted(payload.items()):
                entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (0o100000 | mode) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('Wrote ' + str(output))
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--bundle-kls', action='append', default=[], metavar='darwin-arm64=/absolute/path/kls')
    arguments = parser.parse_args()
    build(arguments.root.resolve(), arguments.bundle_kls)
