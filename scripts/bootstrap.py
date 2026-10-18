#!/usr/bin/env python3
"""Restore pinned development assets. The iOS app itself never downloads anything."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "assets-lock.json").read_text())


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def download(url, destination, expected):
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "asset"
        print(f"Downloading {destination.name}")
        with urllib.request.urlopen(url, timeout=120) as response, path.open("wb") as output:
            shutil.copyfileobj(response, output)
        if digest(path) != expected:
            raise RuntimeError(f"Checksum mismatch: {url}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Check local models/frameworks without downloading")
    parser.add_argument("--upstream", action="store_true", help="Download from original upstream sources instead of Mila's release mirror")
    args = parser.parse_args()
    model = ROOT / "HebrewVoice/Resources/Model"
    for name, item in LOCK["model"].items():
        expected = item["sha256"]
        target = model / name
        if not target.exists() or digest(target) != expected:
            if args.verify_only:
                raise RuntimeError(f"Missing or modified model: {name}")
            base = LOCK["model_upstream_base_url"] if args.upstream else LOCK["model_base_url"]
            download(f"{base}/{name}", target, expected)
        print(f"Verified {name}")
    vendor = ROOT / "Vendor"
    vendor.mkdir(exist_ok=True)
    for item in LOCK["frameworks"]:
        archive = vendor / f'{item["directory"]}.zip'
        framework = vendor / item["directory"]
        if archive.exists():
            if digest(archive) != item["sha256"]:
                raise RuntimeError(f"Modified runtime archive: {archive.name}")
        elif args.verify_only:
            raise RuntimeError(f"Runtime archive required for integrity verification: {archive.name}")
        else:
            url = item["upstream_url"] if args.upstream else item["url"]
            download(url, archive, item["sha256"])
        if not framework.exists():
            if args.verify_only:
                raise RuntimeError(f"Missing framework: {framework.name}")
            with zipfile.ZipFile(archive) as bundle:
                for member in bundle.infolist():
                    resolved = (vendor / member.filename).resolve()
                    if not resolved.is_relative_to(vendor.resolve()):
                        raise RuntimeError("Unsafe archive path")
                bundle.extractall(vendor)
        # Verify every regular file against the checked upstream archive, including the binaries.
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                if member.is_dir():
                    continue
                local = vendor / member.filename
                if not local.is_file():
                    raise RuntimeError(f"Missing runtime file: {member.filename}")
                with bundle.open(member) as source:
                    expected = hashlib.sha256(source.read()).hexdigest()
                if digest(local) != expected:
                    raise RuntimeError(f"Modified runtime file: {member.filename}")
        print(f'Verified {item["directory"]}')
    print("All bundled inference assets are ready. Open HebrewVoice.xcodeproj in Xcode.")


if __name__ == "__main__":
    main()
