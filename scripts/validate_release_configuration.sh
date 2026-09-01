#!/bin/bash

set -eu

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  exit 0
fi

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
invalid=0

is_non_public_host() {
  local host="$1"
  local a b c d

  case "$host" in
    ""|\[*|localhost|*.localhost|*.local|*.internal|example|*.example|example.com|*.example.com|example.net|*.example.net|example.org|*.example.org|*.invalid|*.test)
      return 0
      ;;
  esac

  if [[ "$host" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    a="${BASH_REMATCH[1]}"
    b="${BASH_REMATCH[2]}"
    c="${BASH_REMATCH[3]}"
    d="${BASH_REMATCH[4]}"
    if (( a > 255 || b > 255 || c > 255 || d > 255 )); then
      return 0
    fi
    if (( a == 0 || a == 10 || a == 127 || a >= 224 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 192 && b == 0 && c == 2) ||
          (a == 198 && (b == 18 || b == 19 || b == 51)) ||
          (a == 203 && b == 0 && c == 113) )); then
      return 0
    fi
  fi

  return 1
}

platform_interface="$repository_root/Aster/Sources/PacketTunnel/PacketTunnelPlatformInterface.swift"
if /usr/bin/grep -Eq 'value\(forKeyPath|socket\.fileDescriptor|NSSelectorFromString' "$platform_interface"; then
  echo "error: PacketTunnelPlatformInterface must not access private NetworkExtension implementation details."
  invalid=1
fi

for libbox_header in \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Headers/Libbox.objc.h" \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64_x86_64-simulator/Libbox.framework/Headers/Libbox.objc.h"
do
  if ! /usr/bin/grep -Fq 'FOUNDATION_EXPORT int32_t LibboxGetTunnelFileDescriptor(void);' "$libbox_header"; then
    echo "error: Libbox public tunnel file-descriptor binding is missing from $libbox_header"
    invalid=1
  fi
done

for libbox_binary in \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Libbox" \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64_x86_64-simulator/Libbox.framework/Libbox"
do
  if ! /usr/bin/strings "$libbox_binary" | /usr/bin/grep -Eq -- '-tags=with_utls,with_clash_api,ios(,iossimulator)?,with_low_memory'; then
    echo "error: Libbox must be built with uTLS, internal Clash bootstrap and Network Extension low-memory tags: $libbox_binary"
    invalid=1
  fi
done

privacy_url="${PRIVACY_POLICY_URL:-}"
privacy_host="${privacy_url#https://}"
privacy_host="${privacy_host%%/*}"
privacy_host="${privacy_host%%\?*}"
privacy_host="${privacy_host%%:*}"
privacy_host="$(printf '%s' "$privacy_host" | /usr/bin/tr '[:upper:]' '[:lower:]')"

if [[ ! "$privacy_url" =~ ^https:// ]] || [[ "$privacy_url" == *"@"* ]] || [[ "$privacy_url" == *"#"* ]] || [[ "$privacy_url" == *'$('* ]]; then
  echo "error: A public HTTPS PRIVACY_POLICY_URL is required for Release builds."
  invalid=1
else
  if is_non_public_host "$privacy_host"; then
    echo "error: PRIVACY_POLICY_URL must not use a local or reserved placeholder host."
    invalid=1
  fi
fi

subscription_url="${NODE_SUBSCRIPTION_URL:-}"
subscription_host="${subscription_url#https://}"
subscription_host="${subscription_host%%/*}"
subscription_host="${subscription_host%%\?*}"
subscription_host="${subscription_host%%:*}"
subscription_host="$(printf '%s' "$subscription_host" | /usr/bin/tr '[:upper:]' '[:lower:]')"

# The current App Store release ships a reviewed catalog in the app bundle.
# Keep the remote source optional so a future endpoint can be enabled without
# changing the validation contract again.
if [[ -n "$subscription_url" && "$subscription_url" != *'$('* ]]; then
  if [[ ! "$subscription_url" =~ ^https:// ]] || [[ "$subscription_url" == *"@"* ]] || [[ "$subscription_url" == *"#"* ]]; then
    echo "error: NODE_SUBSCRIPTION_URL must be a public HTTPS URL when configured."
    invalid=1
  elif is_non_public_host "$subscription_host"; then
    echo "error: NODE_SUBSCRIPTION_URL must use a public non-placeholder host."
    invalid=1
  fi
fi

exit "$invalid"
