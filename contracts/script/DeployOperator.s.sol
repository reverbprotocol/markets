// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Operator} from "../src/Operator.sol";

/**
 * Atomic UUPS deploy of Reverb Markets Operator against the shared Safe + TimelockController on
 * Arc testnet. Reads the Safe + Timelock addresses via env (sourced from
 * .deployments/arc-testnet.json) per the shared-Safe-testnet bonus decision; the deployer EOA
 * never holds owner authority past this script.
 *
 * Pipeline (single broadcast):
 *   1. Deploy Operator implementation.
 *   2. Deploy ERC1967Proxy pointing at the implementation.
 *   3. Call initialize on the proxy with:
 *        - admin                = ADMIN_ADDRESS
 *        - disputeEscrow        = DISPUTE_ESCROW_ADDRESS (RefundProtocolFixed proxy from substrate)
 *        - treasury             = TREASURY_ADDRESS
 *        - challengeBond        = CHALLENGE_BOND
 *        - messageTransmitter   = MESSAGE_TRANSMITTER_ADDRESS (default: Arc-testnet predeploy)
 *        - usdc                 = USDC_ADDRESS (default: Arc-testnet predeploy)
 *        - owner                = TIMELOCK_ADDRESS (Timelock controls upgrades + unpause)
 *        - pauser               = SAFE_ADDRESS (Safe pauses without Timelock delay)
 *   4. Read proxy.owner() and assert it equals TIMELOCK_ADDRESS.
 *   5. Print proxy + implementation + owner + pauser.
 *
 * Required env:
 *   DEPLOYER_PRIVATE_KEY
 *   ADMIN_ADDRESS               - market-creator role
 *   DISPUTE_ESCROW_ADDRESS      - deployed RefundProtocolFixed proxy from substrate
 *   TREASURY_ADDRESS            - destination for forfeited challenge bonds
 *   CHALLENGE_BOND              - bond amount in settlement-token units
 *   SAFE_ADDRESS                - the deployed Safe multisig (pauser)
 *   TIMELOCK_ADDRESS            - the deployed TimelockController (owner)
 *
 * Optional env:
 *   EIP712_NAME                 - default "Operator"
 *   EIP712_VERSION              - default "1"
 *   MESSAGE_TRANSMITTER_ADDRESS - Arc testnet 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275 by default
 *   USDC_ADDRESS                - Arc testnet 0x3600000000000000000000000000000000000000 by default
 */
contract DeployOperator is Script {
    address constant DEFAULT_MESSAGE_TRANSMITTER = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;
    address constant DEFAULT_USDC = 0x3600000000000000000000000000000000000000;

    error OwnershipMismatch(address expected, address actual);

    function run() external returns (address proxyAddr, address implAddr) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address escrowAddr = vm.envAddress("DISPUTE_ESCROW_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 bond = vm.envUint("CHALLENGE_BOND");
        address safe = vm.envAddress("SAFE_ADDRESS");
        address timelock = vm.envAddress("TIMELOCK_ADDRESS");
        string memory name = _envOr("EIP712_NAME", "Operator");
        string memory version = _envOr("EIP712_VERSION", "1");
        address mt = _envOrAddr("MESSAGE_TRANSMITTER_ADDRESS", DEFAULT_MESSAGE_TRANSMITTER);
        address usdc = _envOrAddr("USDC_ADDRESS", DEFAULT_USDC);

        vm.startBroadcast(pk);

        Operator impl = new Operator();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                Operator.initialize,
                (admin, escrowAddr, treasury, bond, mt, usdc, name, version, timelock, safe)
            )
        );

        vm.stopBroadcast();

        proxyAddr = address(proxy);
        implAddr = address(impl);

        address actualOwner = Operator(proxyAddr).owner();
        if (actualOwner != timelock) revert OwnershipMismatch(timelock, actualOwner);

        console2.log("Operator proxy           :", proxyAddr);
        console2.log("Operator implementation  :", implAddr);
        console2.log("  owner (TimelockController):", actualOwner);
        console2.log("  pauser (Safe)            :", safe);
        console2.log("  admin                    :", admin);
        console2.log("  disputeEscrow            :", escrowAddr);
        console2.log("  treasury                 :", treasury);
        console2.log("  challengeBond            :", bond);
        console2.log("  messageTransmitter       :", mt);
        console2.log("  usdc                     :", usdc);
    }

    function _envOr(string memory key, string memory dflt) internal view returns (string memory) {
        try vm.envString(key) returns (string memory v) { return v; } catch { return dflt; }
    }

    function _envOrAddr(string memory key, address dflt) internal view returns (address) {
        try vm.envAddress(key) returns (address v) { return v; } catch { return dflt; }
    }
}
