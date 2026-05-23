#!/usr/bin/env bash
# Spin up the full local-dev stack:
#   1. start anvil in the background
#   2. deploy MockUSDC + RefundProtocolFixed + Operator + an example market
#   3. emit a config blob the front-end can paste into its config form
#
# Tear-down with `pkill -f anvil` or by killing the script's anvil child.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ESCROW_DIR="${ROOT}/apps/dispute-escrow"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC_URL="http://127.0.0.1:8545"

export PATH="$HOME/.foundry/bin:$PATH"

echo "==> killing any stale anvil"
pkill -f anvil 2>/dev/null || true
sleep 1

echo "==> starting anvil"
anvil --silent &
ANVIL_PID=$!
sleep 2
echo "    anvil pid: ${ANVIL_PID}"

echo "==> deploying contracts"
DEPLOYER_PRIVATE_KEY="${ANVIL_KEY}" \
  forge script "${ESCROW_DIR}/script/DeployLocal.s.sol" \
  --tc DeployLocal \
  --root "${ESCROW_DIR}" \
  --rpc-url "${RPC_URL}" \
  --broadcast 2>&1 \
  | grep -E "(MockUSDC|disputeEscrow|operator|exampleMarket|chainId|deployer)\s*:" \
  | tee /tmp/reverb-deploy.txt

echo
echo "==> stack live. anvil pid ${ANVIL_PID}. addresses logged to /tmp/reverb-deploy.txt"
echo "    paste into the front-end config panel:"
awk '{print "      "$0}' /tmp/reverb-deploy.txt
echo
echo "    bring it down with: kill ${ANVIL_PID}"
