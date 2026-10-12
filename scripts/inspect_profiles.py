"""Windows diagnostic for an IPA EXPORTED AFTER signing, never proof of install.
Reads CMS-embedded plist only; does not verify certificate/signature trust.
"""
import argparse
import json
import plistlib
import zipfile
from datetime import datetime


def read_profile(raw):
    start = raw.find(b"<?xml")
    if start < 0:
        start = raw.find(b"<plist")
    end = raw.find(b"</plist>", start)
    if start < 0 or end < 0:
        raise ValueError("No XML plist in CMS profile; decode with security cms on macOS")
    return plistlib.loads(raw[start:end + len(b"</plist>")])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as archive:
        result = []
        for name in archive.namelist():
            if name.endswith("/embedded.mobileprovision"):
                profile = read_profile(archive.read(name))
                ent = profile.get("Entitlements", {})
                result.append({"bundle": name.rsplit("/", 1)[0], "expires": str(profile.get("ExpirationDate")),
                               "application_identifier": ent.get("application-identifier"),
                               "healthkit_allowed": ent.get("com.apple.developer.healthkit", False),
                               "device_count": len(profile.get("ProvisionedDevices", [])),
                               "signature_verified": False, "installation_verified": False})
        if not result:
            parser.exit(2, "No profiles found. Unsigned original or signer omitted provisioning.\n")
        print(json.dumps(result, indent=2))
        print("Profiles alone do not prove executable entitlements, Watch UDID inclusion, signature validity or installation.")


if __name__ == "__main__":
    main()
