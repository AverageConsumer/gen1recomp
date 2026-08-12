#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

"${LUA:-luajit}" tests/integration/title_checkpoint_cold_start.lua capture "$test_root"
"${LUA:-luajit}" tests/integration/title_checkpoint_cold_start.lua resume "$test_root"

