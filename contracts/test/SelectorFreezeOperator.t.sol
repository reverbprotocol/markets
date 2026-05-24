// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Operator} from "../src/Operator.sol";
import {ICCTPReceiver} from "@reverbprotocol/protocol/ICCTPReceiver.sol";

/// @notice Selector + event-topic freeze tests for Operator. Locks the on-chain ABI as the
///         regression baseline before any subsequent upgrade. Identical pattern to the substrate
///         repo's freeze test for RefundProtocolFixed.
contract SelectorFreezeOperatorTest is Test {
    // Order tuple serialization for ABI signatures:
    // (address maker, uint256 marketId, uint8 outcome, uint256 price, uint256 size,
    //  uint256 feeBps, bytes32 builder, uint256 salt, uint256 expiry)
    string constant ORDER_TUPLE = "(address,uint256,uint8,uint256,uint256,uint256,bytes32,uint256,uint256)";

    // ---------- external function selectors ----------

    function test_selectorFrozen_DOMAIN_SEPARATOR() public pure {
        assertEq(Operator.DOMAIN_SEPARATOR.selector, bytes4(keccak256("DOMAIN_SEPARATOR()")));
    }

    function test_selectorFrozen_createMarket() public pure {
        assertEq(
            Operator.createMarket.selector,
            bytes4(keccak256("createMarket(bytes32,address,address,uint64,uint32)"))
        );
    }

    function test_selectorFrozen_hashOrder() public pure {
        assertEq(
            Operator.hashOrder.selector,
            bytes4(keccak256(abi.encodePacked("hashOrder(", ORDER_TUPLE, ")")))
        );
    }

    function test_selectorFrozen_matchOrders() public pure {
        assertEq(
            Operator.matchOrders.selector,
            bytes4(keccak256(abi.encodePacked(
                "matchOrders(",
                ORDER_TUPLE,
                ",bytes,",
                ORDER_TUPLE,
                ",bytes,uint256)"
            )))
        );
    }

    function test_selectorFrozen_proposeResolution() public pure {
        assertEq(Operator.proposeResolution.selector, bytes4(keccak256("proposeResolution(uint256,uint8)")));
    }

    function test_selectorFrozen_challengeResolution() public pure {
        assertEq(Operator.challengeResolution.selector, bytes4(keccak256("challengeResolution(uint256)")));
    }

    function test_selectorFrozen_arbiterFinalizeDispute() public pure {
        assertEq(
            Operator.arbiterFinalizeDispute.selector,
            bytes4(keccak256("arbiterFinalizeDispute(uint256,uint8,bool)"))
        );
    }

    function test_selectorFrozen_settle() public pure {
        assertEq(Operator.settle.selector, bytes4(keccak256("settle(uint256)")));
    }

    function test_selectorFrozen_redeem() public pure {
        assertEq(Operator.redeem.selector, bytes4(keccak256("redeem(uint256)")));
    }

    function test_selectorFrozen_withdrawBuilderFees() public pure {
        assertEq(
            Operator.withdrawBuilderFees.selector,
            bytes4(keccak256("withdrawBuilderFees(bytes32,address,address)"))
        );
    }

    function test_selectorFrozen_onCCTPReceive() public pure {
        // Inherited from CCTPReceiverMixin via the substrate's ICCTPReceiver interface.
        assertEq(ICCTPReceiver.onCCTPReceive.selector, bytes4(keccak256("onCCTPReceive(bytes,bytes)")));
    }

    // ---------- event topic hashes ----------

    function test_eventTopicFrozen_MarketCreated() public pure {
        assertEq(
            Operator.MarketCreated.selector,
            keccak256("MarketCreated(uint256,bytes32,address,address,uint64,uint32)")
        );
    }

    function test_eventTopicFrozen_OrderFilled() public pure {
        assertEq(
            Operator.OrderFilled.selector,
            keccak256(
                "OrderFilled(bytes32,bytes32,uint256,address,address,uint256,uint256,uint256,bytes32,bytes32)"
            )
        );
    }

    function test_eventTopicFrozen_BuilderFeeAccrued() public pure {
        assertEq(Operator.BuilderFeeAccrued.selector, keccak256("BuilderFeeAccrued(bytes32,address,uint256)"));
    }

    function test_eventTopicFrozen_BuilderFeeWithdrawn() public pure {
        assertEq(
            Operator.BuilderFeeWithdrawn.selector,
            keccak256("BuilderFeeWithdrawn(bytes32,address,address,uint256)")
        );
    }

    function test_eventTopicFrozen_ResolutionProposed() public pure {
        assertEq(
            Operator.ResolutionProposed.selector,
            keccak256("ResolutionProposed(uint256,uint8,uint64)")
        );
    }

    function test_eventTopicFrozen_ResolutionChallenged() public pure {
        assertEq(
            Operator.ResolutionChallenged.selector,
            keccak256("ResolutionChallenged(uint256,address,uint256)")
        );
    }

    function test_eventTopicFrozen_DisputeFinalized() public pure {
        assertEq(Operator.DisputeFinalized.selector, keccak256("DisputeFinalized(uint256,uint8,bool)"));
    }

    function test_eventTopicFrozen_MarketSettled() public pure {
        assertEq(Operator.MarketSettled.selector, keccak256("MarketSettled(uint256,uint8)"));
    }

    function test_eventTopicFrozen_Redeemed() public pure {
        assertEq(Operator.Redeemed.selector, keccak256("Redeemed(uint256,address,uint256)"));
    }

    function test_eventTopicFrozen_FollowerDepositReceived() public pure {
        assertEq(
            Operator.FollowerDepositReceived.selector,
            keccak256("FollowerDepositReceived(uint256,address,uint256)")
        );
    }
}
