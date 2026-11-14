"""Assemble the product's CEF runtime bundles. Does not launch or register apps."""
import argparse
import json
from cef_identity import require_lock, tree_digest
import plistlib
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('--cef-root', type=Path, required=True)
    parser.add_argument('--cef-lock', type=Path, required=True)
    parser.add_argument('--configuration', type=Path, required=True)
    args = parser.parse_args()
    engine = require_lock(args.cef_root, args.cef_lock)
    frameworks = args.app / 'Contents/Frameworks'
    frameworks.mkdir(exist_ok=True)
    source = args.cef_root / 'Release/Chromium Embedded Framework.framework'
    destination = frameworks / source.name
    receipt = args.app.with_suffix('.cef-receipt.json')
    if destination.exists():
        if not receipt.exists():
            raise ValueError('Existing framework has no build receipt. Preserve the app and use a new build directory.')
        previous = json.loads(receipt.read_text())
        if previous['engine'] != engine or previous['signed_framework_sha256'] != tree_digest(destination):
            raise ValueError('Bundled CEF differs from the locked engine. Use a new build directory; no replacement performed.')
    else:
        shutil.copytree(source, destination, symlinks=True)
        if tree_digest(destination) != engine['sha256']['Release/Chromium Embedded Framework.framework']:
            raise ValueError('CEF copy is incomplete; preserving output for inspection.')
    template = plistlib.loads((args.configuration / 'Helper-Info.plist').read_bytes())
    for suffix in ['', ' (Alerts)', ' (GPU)', ' (Plugin)', ' (Renderer)']:
        name = 'JenaWeb Helper' + suffix
        app = frameworks / (name + '.app')
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.helper, contents / 'MacOS' / name)
        identity_suffix = suffix.replace(' ', '').replace('(', '.').replace(')', '').lower()
        metadata = dict(template)
        metadata.update(CFBundleExecutable=name, CFBundleIdentifier='local.jena.web.helper' + identity_suffix,
                        CFBundleName=name, CFBundleDisplayName='Jena Web 알림' if suffix == ' (Alerts)' else name)
        (contents / 'Info.plist').write_bytes(plistlib.dumps(metadata))
    # Development signature only. Distribution signing/notarization is separate.
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(args.app)], check=True)
    # Signing changes Mach-O bytes. Compare subsequent builds with the signed copy,
    # while retaining the independent digest of the original distribution.
    record = {'engine': engine, 'signed_framework_sha256': tree_digest(destination)}
    # Receipt is outside the signed app so updating it cannot invalidate the seal.
    external_receipt = args.app.with_suffix('.cef-receipt.json')
    external_receipt.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
