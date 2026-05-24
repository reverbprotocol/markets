// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";
import {Operator} from "../src/Operator.sol";

/**
 * One-shot local deployment for demo + front-end smoke testing.
 *
 * Pipeline:
 *   1. Deploy MockUSDC (DEMO ONLY).
 *   2. Mint 1_000_000 MockUSDC to the deployer.
 *   3. Deploy RefundProtocolFixed implementation + ERC1967 proxy; initialize with
 *      arbiter = deployer, owner = deployer, pauser = deployer.
 *   4. Deploy Operator implementation + ERC1967 proxy; initialize with admin = deployer,
 *      treasury = deployer, messageTransmitter = deployer (placeholder), owner = deployer,
 *      pauser = deployer.
 *   5. Create one example market.
 *   6. Print every address + the example market id.
 *
 * Run against local anvil:
 *   anvil &
 *   DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
 *
 * NEVER use this script against a real chain. The MockUSDC is unrestricted-mint and the
 * deployer collapses every role.
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

        RefundProtocolFixed escrowImpl = new RefundProtocolFixed();
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(escrowImpl),
            abi.encodeCall(
                RefundProtocolFixed.initialize,
                (deployer, address(usdc), "RefundProtocolFixed", "1", deployer, deployer)
            )
        );
        RefundProtocolFixed escrow = RefundProtocolFixed(address(escrowProxy));

        Operator opImpl = new Operator();
        ERC1967Proxy opProxy = new ERC1967Proxy(
            address(opImpl),
            abi.encodeCall(
                Operator.initialize,
                (
                    deployer,
                    address(escrow),
                    deployer,
                    100 * 1e6,
                    deployer, // messageTransmitter placeholder for local
                    address(usdc),
                    "Operator",
                    "1",
                    deployer,
                    deployer
                )
            )
        );
        Operator op = Operator(address(opProxy));

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
        console2.log("escrow proxy   :", address(escrow));
        console2.log("escrow impl    :", address(escrowImpl));
        console2.log("operator proxy :", address(op));
        console2.log("operator impl  :", address(opImpl));
        console2.log("example market :", marketId);
    }
}
