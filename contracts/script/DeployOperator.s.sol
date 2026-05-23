// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Operator} from "../src/Operator.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";

/**
 * Deploy the Operator. Requires RefundProtocolFixed already deployed.
 *
 * Required env:
 *   DEPLOYER_PRIVATE_KEY
 *   ADMIN_ADDRESS              - market-creator role
 *   DISPUTE_ESCROW_ADDRESS     - deployed RefundProtocolFixed
 *   TREASURY_ADDRESS           - destination for forfeited challenge bonds
 *   CHALLENGE_BOND             - bond amount in settlement-token units (e.g. 100_000000 for 100 USDC at 6 dp)
 *
 * Optional env:
 *   EIP712_NAME                - default "Operator"
 *   EIP712_VERSION             - default "1"
 */
contract DeployOperator is Script {
    function run() external returns (Operator op) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address escrowAddr = vm.envAddress("DISPUTE_ESCROW_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 bond = vm.envUint("CHALLENGE_BOND");
        string memory name = _envOr("EIP712_NAME", "Operator");
        string memory version = _envOr("EIP712_VERSION", "1");

        vm.startBroadcast(pk);
        op = new Operator(admin, RefundProtocolFixed(escrowAddr), treasury, bond, name, version);
        vm.stopBroadcast();

        console2.log("Operator deployed at:", address(op));
        console2.log("  admin         :", admin);
        console2.log("  disputeEscrow :", escrowAddr);
        console2.log("  treasury      :", treasury);
        console2.log("  challengeBond :", bond);
    }

    function _envOr(string memory key, string memory dflt) internal view returns (string memory) {
        try vm.envString(key) returns (string memory v) { return v; } catch { return dflt; }
    }
}
