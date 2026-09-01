#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$repository_root/scripts/build_core.sh" "$@"
