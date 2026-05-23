// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";
import {Operator} from "../src/Operator.sol";

/**
 * One-shot local deployment for demo + front-end smoke testing.
 *
 * Pipeline:
 *   1. Deploy MockUSDC (DEMO ONLY).
 *   2. Mint 1_000_000 MockUSDC to the deployer + admin + arbiter + treasury.
 *   3. Deploy RefundProtocolFixed (deployer = arbiter).
 *   4. Deploy Operator (admin = deployer, arbiter = deployer, treasury = deployer).
 *   5. Create one example market resolving 1 hour from now with a 5-minute challenge window.
 *   6. Print every address + the example market id.
 *
 * Run against local anvil:
 *   anvil &
 *   DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
 *
 * NEVER use this script against a real chain. The MockUSDC is unrestricted-mint and the
 * arbiter / admin / treasury all collapse to the deployer key.
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin (DEMO)", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract DeployLocal is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockUSDC usdc = new MockUSDC();
        usdc.mint(deployer, 1_000_000 * 1e6);

        RefundProtocolFixed escrow = new RefundProtocolFixed(
            deployer,
            address(usdc),
            "RefundProtocolFixed",
            "1"
        );

        Operator op = new Operator(
            deployer,
            escrow,
            deployer,
            100 * 1e6,
            deployer, // messageTransmitter placeholder for local
            address(usdc),
            "Operator",
            "1"
        );

        uint256 marketId = op.createMarket(
            keccak256("DEMO: example market resolving in 1h"),
            IERC20(address(usdc)),
            deployer,
            uint64(block.timestamp + 1 hours),
            5 minutes
        );

        vm.stopBroadcast();

        console2.log("---- LOCAL DEPLOYMENT ----");
        console2.log("chainId        :", block.chainid);
        console2.log("deployer       :", deployer);
        console2.log("MockUSDC       :", address(usdc));
        console2.log("disputeEscrow  :", address(escrow));
        console2.log("operator       :", address(op));
        console2.log("exampleMarket  :", marketId);
        console2.log("--------------------------");
    }
}
