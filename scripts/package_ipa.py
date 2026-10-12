"""Run on macOS after xcodebuild. A ZIP package is NOT a signing/install success."""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
from pathlib import Path


def inspect(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    watches = list((app / "Watch").glob("*.app")) + list((app / "PlugIns").glob("*.app"))
    if len(watches) != 1:
        raise ValueError(f"Expected exactly one embedded Watch app, found {watches}")
    watch = watches[0]
    wi = plistlib.loads((watch / "Info.plist").read_bytes())
    if wi.get("WKCompanionAppBundleIdentifier") != info["CFBundleIdentifier"]:
        raise ValueError("Watch companion ID does not match iPhone ID")
    if not wi.get("WKApplication") or "watchos" not in str(wi.get("CFBundleSupportedPlatforms", [])).lower():
        raise ValueError("Embedded app is not a watchOS WKApplication")
    for root, pi in [(app, info), (watch, wi)]:
        if not (root / pi["CFBundleExecutable"]).is_file():
            raise ValueError(f"Missing executable: {root}")
    return {"phone_id": info["CFBundleIdentifier"], "watch_id": wi["CFBundleIdentifier"],
            "watch_path": str(watch.relative_to(app)), "watch_minimum_os": wi.get("MinimumOSVersion"),
            "phone_minimum_os": info.get("MinimumOSVersion"), "signed": False,
            "watch_installation_verified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    report = inspect(args.app)
    staging = args.output / "staging"
    if staging.exists():
        raise ValueError("Staging already exists; use a fresh output directory")
    payload = staging / "Payload"
    payload.mkdir(parents=True)
    copied = payload / args.app.name
    shutil.copytree(args.app, copied, symlinks=True)
    # Preserve executable bits and ZIP layout through Apple's ditto.
    ipa = args.output.resolve() / "ThreeMin-unsigned.ipa"
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "Payload", str(ipa)], cwd=staging, check=True)
    report["sha256"] = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (args.output / "package-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    shutil.rmtree(staging)  # only this fixed local staging directory created above
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
