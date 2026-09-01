#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
archive_path="${1:-}"

if [[ -z "$archive_path" ]]; then
  echo "error: pass the path to one signed .xcarchive."
  exit 2
fi
if [[ ! -d "$archive_path" || "$archive_path" != *.xcarchive ]]; then
  echo "error: archive path must be an existing .xcarchive directory."
  exit 2
fi

shopt -s nullglob
applications=("$archive_path/Products/Applications/"*.app)
if [[ "${#applications[@]}" -ne 1 ]]; then
  echo "error: expected exactly one application in the archive."
  exit 1
fi
app_path="${applications[0]}"
app_info="$app_path/Info.plist"

extensions=("$app_path/PlugIns/"*.appex)
if [[ "${#extensions[@]}" -ne 1 || "${extensions[0]##*/}" != "PacketTunnel.appex" ]]; then
  echo "error: the signed archive must contain exactly one PacketTunnel.appex."
  exit 1
fi
extension_path="${extensions[0]}"
extension_info="$extension_path/Info.plist"

for required_path in \
  "$app_info" \
  "$extension_info" \
  "$app_path/PrivacyInfo.xcprivacy" \
  "$extension_path/Frameworks/Libbox.framework/Libbox"
do
  if [[ ! -e "$required_path" ]]; then
    echo "error: required archive component is missing: $required_path"
    exit 1
  fi
done

if find "$app_path" -type d -name '*.xctest' -print -quit | /usr/bin/grep -q .; then
  echo "error: XCTest bundle leaked into the archived application."
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/codesign --verify --strict "$extension_path"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
app_entitlements="$temporary_directory/app-entitlements.plist"
extension_entitlements="$temporary_directory/extension-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$app_path" > "$app_entitlements" 2>/dev/null
/usr/bin/codesign -d --entitlements :- "$extension_path" > "$extension_entitlements" 2>/dev/null

for entitlements in "$app_entitlements" "$extension_entitlements"
do
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.developer.networking.networkextension:0' \
    "$entitlements" | /usr/bin/grep -qx 'packet-tunnel-provider' || {
      echo "error: packet-tunnel-provider entitlement is missing from $entitlements"
      exit 1
    }
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.application-groups:0' \
    "$entitlements" | /usr/bin/grep -qx 'group.com.astervpn.shared' || {
      echo "error: App Group entitlement is missing from $entitlements"
      exit 1
    }
done

privacy_url="$(/usr/libexec/PlistBuddy -c 'Print :AsterPrivacyPolicyURL' "$app_info")"
subscription_url="$(/usr/libexec/PlistBuddy -c 'Print :AsterNodeSubscriptionURL' "$app_info" 2>/dev/null || true)"
if [[ "$subscription_url" == '$('* || "$subscription_url" == "(null)" ]]; then
  subscription_url=""
fi

CONFIGURATION=Release \
PRIVACY_POLICY_URL="$privacy_url" \
NODE_SUBSCRIPTION_URL="$subscription_url" \
  "$repository_root/scripts/validate_release_configuration.sh"

/usr/bin/nm -gU "$extension_path/PacketTunnel" 2>/dev/null \
  | /usr/bin/grep -q '_LibboxGetTunnelFileDescriptor$' || {
    echo "error: archived PacketTunnel does not export its public utun file-descriptor bridge."
    exit 1
  }

echo "Signed archive validation passed: $app_path"
