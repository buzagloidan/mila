#!/usr/bin/env python3
"""Package tracked source plus verified model/runtime assets, without signing material."""
import argparse
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/releases/Mila-1.0-build-2-source-with-assets.zip")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "scripts/bootstrap.py"), "--verify-only"], check=True)
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    paths = {Path(p) for p in tracked if p}
    paths.update(Path("HebrewVoice/Resources/Model") / name for name in
                 ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"])
    paths.update(Path("Vendor") / name for name in ["sherpa-onnx.xcframework.zip", "onnxruntime.xcframework.zip"])
    forbidden = {".p8", ".p12", ".pfx", ".pem", ".key", ".mobileprovision", ".provisionprofile", ".ipa"}
    for path in paths:
        if path.is_absolute() or ".." in path.parts or path.suffix in forbidden or ".local." in path.name:
            raise RuntimeError(f"Refusing to package private or unsafe path: {path}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(paths):
            bundle.write(ROOT / path, Path("mila") / path)
    print(f"Packaged {len(paths)} files: {args.output}")
    print("After extracting, run python3 scripts/bootstrap.py to unpack local frameworks without network access.")


if __name__ == "__main__":
    main()
