#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

validate_https_url() {
  setting_name="$1"
  setting_value="$2"

  case "$setting_value" in
    https://*) ;;
    *)
      echo "error: $setting_name must be an absolute HTTPS URL for Release."
      exit 1
      ;;
  esac

  case "$setting_value" in
    *example.com*|*.example|*.example:*|*.example/*|\
    *.invalid|*.invalid:*|*.invalid/*|*.test|*.test:*|*.test/*|\
    *.localhost|*.localhost:*|*.localhost/*|*.local|*.local:*|*.local/*|\
    *://localhost|*://localhost:*|*://127.*|*://0.*|*://10.*|\
    *://169.254.*|*://192.168.*|*://172.1[6-9].*|*://172.2[0-9].*|\
    *://172.3[01].*|*://\[::1\]*|*://\[fc*|*://\[fd*|*://\[fe8*|\
    *://\[fe9*|*://\[fea*|*://\[feb*)
      echo "error: $setting_name still contains a placeholder, special-use, loopback, or private host."
      exit 1
      ;;
  esac
}

validate_https_url "ASTER_API_BASE_URL" "${ASTER_API_BASE_URL:-}"
validate_https_url "ASTER_PUBLIC_SITE_BASE_URL" "${ASTER_PUBLIC_SITE_BASE_URL:-}"
validate_https_url "ASTER_PRIVACY_POLICY_URL" "${ASTER_PRIVACY_POLICY_URL:-}"
validate_https_url "ASTER_TERMS_OF_SERVICE_URL" "${ASTER_TERMS_OF_SERVICE_URL:-}"
validate_https_url "ASTER_SUPPORT_URL" "${ASTER_SUPPORT_URL:-}"

if [ "${ASTER_PACKET_TUNNEL_TRANSPORT_AVAILABLE:-NO}" != "YES" ]; then
  echo "error: Release requires a reviewed and linked VPN transport."
  exit 1
fi

transport_provider="${SRCROOT:-}/AsterPacketTunnel/PacketTunnelProvider.swift"
if [ ! -f "$transport_provider" ]; then
  echo "error: PacketTunnelProvider source was not available to the Release validator."
  exit 1
fi

if grep -q 'completionHandler(PacketTunnelError.transportNotInstalled)' "$transport_provider"; then
  echo "error: PacketTunnelProvider still contains the fail-closed placeholder implementation."
  exit 1
fi
