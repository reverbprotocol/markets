#!/usr/bin/env bash
# Smoke verify the four Reverb Markets persona binaries: each must build, mint or load its
# ed25519 hid, load its EOA private key, compose its PersonaForager, and print the
# resulting hid + tool surface + allowed_contracts to stdout. Exit non-zero on any failure.
#
# Run after `scripts/mint-markets-personas.sh` has minted the per-persona EOA keys.

set -euo pipefail

VARIANT="${VARIANT:-default}"
BINS=(
  "markets-auto-create:mkac:1"   # 1 tool of write capability: create_market
  "markets-auto-resolve:mkar:1"  # 1 write: resolve_market
  "markets-auto-dispute:mkad:1"  # 1 write: file_dispute
  "markets-arbiter:mkarb:1"      # 1 write: rule_dispute
)
EXPECTED_TOOLS_TOTAL=(
  "markets-auto-create:4"   # 1 write + 3 reads/subscribe
  "markets-auto-resolve:3"
  "markets-auto-dispute:3"
  "markets-arbiter:3"
)

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building markets persona binaries..."
( cd "$repo_root" && cargo build --quiet \
    --bin markets-auto-create \
    --bin markets-auto-resolve \
    --bin markets-auto-dispute \
    --bin markets-arbiter )

failures=0

for entry in "${EXPECTED_TOOLS_TOTAL[@]}"; do
  bin="${entry%%:*}"
  expected="${entry##*:}"
  bee_name="${bin}-${VARIANT}"
  key_file="${HOME}/.config/hum/${bee_name}/key.hex"

  echo
  echo "=== ${bin} ==="

  if [[ ! -f "$key_file" ]]; then
    echo "  FAIL: missing keyfile at ${key_file}. run scripts/mint-markets-personas.sh first." >&2
    failures=$((failures + 1))
    continue
  fi

  out=$( "${repo_root}/target/debug/${bin}" "${VARIANT}" 2>&1 ) || {
    echo "  FAIL: ${bin} exited non-zero" >&2
    echo "$out" | sed 's/^/    /' >&2
    failures=$((failures + 1))
    continue
  }

  hid=$(echo "$out" | awk -F': ' '/^hid:/ {print $2}')
  tools=$(echo "$out" | awk -F': ' '/^tools:/ {print $2}')
  tool_count=$(echo "$tools" | awk -F', ' '{print NF}')

  if [[ -z "$hid" ]] || [[ "$hid" != fbee_* ]]; then
    echo "  FAIL: hid missing or wrong prefix: ${hid:-<empty>}" >&2
    failures=$((failures + 1))
    continue
  fi

  if [[ "${#hid}" -ne 69 ]]; then
    echo "  FAIL: hid wrong length: ${#hid} (expected 69)" >&2
    failures=$((failures + 1))
    continue
  fi

  if [[ "$tool_count" -ne "$expected" ]]; then
    echo "  FAIL: tool count ${tool_count} != expected ${expected}" >&2
    echo "    tools: ${tools}" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "  PASS"
  echo "    hid: ${hid}"
  echo "    tools (${tool_count}): ${tools}"
done

echo
if [[ "$failures" -gt 0 ]]; then
  echo "smoke verification: ${failures} persona(s) failed" >&2
  exit 1
fi

echo "smoke verification: all four personas boot cleanly with valid hids and scoped tool surfaces."
