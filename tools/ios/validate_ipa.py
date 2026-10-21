"""Check iOS packaging and, on macOS, the signed VPN entitlement contract."""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile
import zipfile

APP_ID = "com.lokinetwork.v2rayVpn"
GROUP = "group.com.lokinetwork.v2rayVpn"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(path, signed=False):
    with zipfile.ZipFile(path) as archive:
        app_roots = [n[:-len("Info.plist")] for n in archive.namelist()
                     if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        require(len(app_roots) == 1, "IPA must contain exactly one main app")
        root = app_roots[0]
        extension = root + "PlugIns/XrayTunnel.appex/"
        app = plistlib.loads(archive.read(root + "Info.plist"))
        tunnel = plistlib.loads(archive.read(extension + "Info.plist"))
        require(app["CFBundleIdentifier"] == APP_ID, "Unexpected app bundle ID")
        require(tunnel["CFBundleIdentifier"] == APP_ID + ".XrayTunnel", "Unexpected extension bundle ID")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            require(app[key] == tunnel[key], "App/extension version mismatch: " + key)
        for prefix, info in ((root, app), (extension, tunnel)):
            executable = info["CFBundleExecutable"]
            require("/" not in executable and "\\" not in executable, "Invalid executable name")
            require(archive.getinfo(prefix + executable).file_size > 0, "Missing executable")
        if signed:
            with tempfile.TemporaryDirectory(prefix="loki-ipa-check-") as temporary:
                destination = pathlib.Path(temporary).resolve()
                for entry in archive.infolist():
                    target = (destination / entry.filename).resolve()
                    require(target.is_relative_to(destination), "Unsafe IPA entry")
                archive.extractall(destination)
                teams = []
                for prefix in (root, extension):
                    bundle = destination / prefix
                    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True, capture_output=True)
                    entitlements = subprocess.run(
                        ["codesign", "-d", "--entitlements", ":-", str(bundle)],
                        check=True, capture_output=True,
                    )
                    rights = plistlib.loads(entitlements.stdout)
                    require("packet-tunnel-provider" in rights.get("com.apple.developer.networking.networkextension", []),
                            "Signed app and extension both require Packet Tunnel entitlement")
                    require(GROUP in rights.get("com.apple.security.application-groups", []),
                            "Signed app and extension both require the registered App Group")
                    team = rights.get("com.apple.developer.team-identifier")
                    require(bool(team), "Missing Apple Team entitlement")
                    teams.append(team)
                require(teams[0] == teams[1], "App and extension must use the same Apple Team")
        return app["CFBundleShortVersionString"], app["CFBundleVersion"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--signed", action="store_true")
    mode.add_argument("--unsigned", action="store_true")
    parser.add_argument("ipa")
    args = parser.parse_args()
    version, build = validate(args.ipa, signed=args.signed)
    print(f"Verified iOS packaging: {version}+{build}")
    if args.unsigned:
        print("UNSIGNED compilation artifact only. VPN requires valid app and extension signing/provisioning.")
