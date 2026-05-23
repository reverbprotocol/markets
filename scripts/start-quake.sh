#!/usr/bin/env bash
# Spin up the full local arc-devnet stack via quake:
#   1. ensure colima is up so docker is reachable
#   2. quake setup + build + start (3-validator scenario)
#   3. wait for the network to produce blocks
#   4. deploy MockUSDC + RefundProtocolFixed + Operator + an example market
#      against validator1's RPC (localhost:8545)
#
# Tear-down: `apps/scripts/stop-quake.sh` (sibling) or `quake clean`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ESCROW_DIR="${ROOT}/apps/dispute-escrow"
ARC_NODE_DIR="${ROOT}/repos/arc-node"
QUAKE="${ARC_NODE_DIR}/target/release/quake"
SCENARIO="${ARC_NODE_DIR}/crates/quake/scenarios/examples/3nodes.toml"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC_URL="http://127.0.0.1:8545"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v "${QUAKE}" >/dev/null && [ ! -x "${QUAKE}" ]; then
  echo "quake binary not found at ${QUAKE}. build it first:"
  echo "  cargo build -p quake --release --manifest-path ${ARC_NODE_DIR}/Cargo.toml"
  exit 1
fi

echo "==> verifying docker is reachable (colima)"
if ! docker info >/dev/null 2>&1; then
  echo "    docker daemon not reachable. start colima first:"
  echo "      colima start --cpu 4 --memory 6 --disk 30"
  exit 1
fi

echo "==> quake setup (3 validators)"
"${QUAKE}" -f "${SCENARIO}" setup

echo "==> quake build (docker images for CL + EL; may take several minutes on first run)"
"${QUAKE}" build

echo "==> quake start"
"${QUAKE}" start

echo "==> waiting for validator1 to reach height 3 (means consensus is live)"
"${QUAKE}" wait height 3 validator1

echo "==> chain live. deploying contracts via DeployLocal.s.sol against ${RPC_URL}"
DEPLOYER_PRIVATE_KEY="${ANVIL_KEY}" \
  forge script "${ESCROW_DIR}/script/DeployLocal.s.sol" \
  --tc DeployLocal \
  --root "${ESCROW_DIR}" \
  --rpc-url "${RPC_URL}" \
  --broadcast 2>&1 \
  | grep -E "(MockUSDC|disputeEscrow|operator|exampleMarket|chainId|deployer)\s*:" \
  | tee /tmp/reverb-deploy.txt

echo
echo "==> arc-devnet stack live. addresses logged to /tmp/reverb-deploy.txt"
echo "    paste into the front-end config panel (chain id 1337, same as anvil):"
awk '{print "      "$0}' /tmp/reverb-deploy.txt
echo
echo "    bring it down with: ${QUAKE} clean"
