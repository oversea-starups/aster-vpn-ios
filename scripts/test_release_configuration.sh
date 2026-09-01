#!/bin/bash

set -eu

validator="$(cd "$(dirname "$0")" && pwd)/validate_release_configuration.sh"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
production_node_subscription_url="https://locations.astervpn.com/subscription/token"

expect_success() {
  if ! env "$@" "$validator" >/dev/null 2>&1; then
    echo "error: expected release configuration to pass: $*"
    exit 1
  fi
}

expect_failure() {
  if env "$@" "$validator" >/dev/null 2>&1; then
    echo "error: expected release configuration to fail: $*"
    exit 1
  fi
}

expect_success CONFIGURATION=Debug
expect_success CONFIGURATION=Release PRIVACY_POLICY_URL=https://privacy.astervpn.com/privacy NODE_SUBSCRIPTION_URL="$production_node_subscription_url"
expect_success CONFIGURATION=Release PRIVACY_POLICY_URL=https://privacy.astervpn.com/privacy
expect_failure CONFIGURATION=Release PRIVACY_POLICY_URL=http://privacy.astervpn.com/privacy NODE_SUBSCRIPTION_URL="$production_node_subscription_url"
expect_failure CONFIGURATION=Release PRIVACY_POLICY_URL=https://localhost/privacy NODE_SUBSCRIPTION_URL="$production_node_subscription_url"
expect_failure CONFIGURATION=Release PRIVACY_POLICY_URL=https://privacy.astervpn.com/privacy NODE_SUBSCRIPTION_URL=http://locations.astervpn.com/subscription/token
expect_failure CONFIGURATION=Release PRIVACY_POLICY_URL=https://privacy.astervpn.com/privacy NODE_SUBSCRIPTION_URL=https://192.168.1.2/subscription/token
expect_failure CONFIGURATION=Release PRIVACY_POLICY_URL=https://user@privacy.astervpn.com/privacy NODE_SUBSCRIPTION_URL="$production_node_subscription_url"

for entitlement in \
  "$repository_root/Aster/Config/Aster.entitlements" \
  "$repository_root/Aster/Config/PacketTunnel.entitlements"
do
  /usr/libexec/PlistBuddy -c "Print :com.apple.developer.networking.networkextension:0" "$entitlement" | grep -qx "packet-tunnel-provider" || { echo "error: packet tunnel entitlement is missing from $entitlement"; exit 1; }
  /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$entitlement" | grep -qx "group.com.astervpn.shared" || { echo "error: app group entitlement is missing from $entitlement"; exit 1; }
done

platform_interface="$repository_root/Aster/Sources/PacketTunnel/PacketTunnelPlatformInterface.swift"
if grep -Eq 'value\(forKeyPath|socket\.fileDescriptor|NSSelectorFromString' "$platform_interface"; then
  echo "error: private NetworkExtension implementation access remains in $platform_interface"
  exit 1
fi

for libbox_binary in \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Libbox" \
  "$repository_root/Aster/Frameworks/Libbox.xcframework/ios-arm64_x86_64-simulator/Libbox.framework/Libbox"
do
  /usr/bin/nm -gU "$libbox_binary" 2>/dev/null | grep -q '_LibboxGetTunnelFileDescriptor$' || { echo "error: LibboxGetTunnelFileDescriptor is not exported by $libbox_binary"; exit 1; }
done

echo "Release configuration validation tests passed."
