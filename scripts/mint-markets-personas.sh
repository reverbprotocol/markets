#!/usr/bin/env bash
# Mint one EOA private key per Reverb Markets persona binary into
# ~/.config/hum/<bee_name>/key.hex at 0600. Idempotent: existing keys are preserved.
#
# Persona bee names follow the convention `markets-<role>-<variant>`. This script defaults
# variant to `default`; pass `VARIANT=foo` to override. The four binaries the markets
# workspace ships are: markets-auto-create, markets-auto-resolve, markets-auto-dispute,
# markets-arbiter.
#
# Each minted key is a fresh secp256k1 keypair generated via `cast wallet new`. The address
# is printed at the end so it can be funded on Arc testnet via the Circle faucet.
#
# Dependencies: foundry (cast).

set -euo pipefail

VARIANT="${VARIANT:-default}"
ROLES=(
  "markets-auto-create"
  "markets-auto-resolve"
  "markets-auto-dispute"
  "markets-arbiter"
)

if ! command -v cast >/dev/null 2>&1; then
  echo "error: cast not found. install foundry first: https://book.getfoundry.sh/getting-started/installation" >&2
  exit 1
fi

mint_one() {
  local bee_name="$1"
  local dir="${HOME}/.config/hum/${bee_name}"
  local key_file="${dir}/key.hex"

  mkdir -p "$dir"
  chmod 700 "$dir"

  if [[ -f "$key_file" ]]; then
    local addr
    addr=$(cast wallet address --private-key "$(cat "$key_file")")
    echo "  ${bee_name}: existing key, address ${addr}"
    return 0
  fi

  local out priv addr
  out=$(cast wallet new)
  priv=$(echo "$out" | awk -F': ' '/Private key/ {print $2}')
  addr=$(echo "$out" | awk -F': ' '/Address/ {print $2}')

  printf '%s\n' "$priv" > "$key_file"
  chmod 600 "$key_file"

  echo "  ${bee_name}: minted, address ${addr}"
}

echo "Minting per-persona EOA keys (variant=${VARIANT}):"
for role in "${ROLES[@]}"; do
  mint_one "${role}-${VARIANT}"
done

echo
echo "Each persona binary will load its key from \$HOME/.config/hum/<bee>/key.hex."
echo "Fund each address with Arc testnet USDC at https://faucet.circle.com before running."
