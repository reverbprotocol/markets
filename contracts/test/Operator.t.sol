// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Operator} from "../src/Operator.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Mock CCTP MessageTransmitterV2 for unit tests. Credits a configured amount of USDC to
///      the caller on each `receiveMessage` call.
contract MockMessageTransmitterV2 {
    MockUSDC public usdc;
    uint256 public mintAmount;

    constructor(address _usdc) { usdc = MockUSDC(_usdc); }
    function setMintAmount(uint256 a) external { mintAmount = a; }

    function receiveMessage(bytes calldata, bytes calldata) external returns (bool) {
        if (mintAmount > 0) usdc.mint(msg.sender, mintAmount);
        return true;
    }
}

contract OperatorTest is Test {
    Operator public op;
    RefundProtocolFixed public escrow;
    MockUSDC public usdc;
    MockMessageTransmitterV2 public mt;

    uint256 constant ALICE_PK = 0xA11CE;
    uint256 constant BOB_PK = 0xB0B;
    uint256 constant CAROL_PK = 0xCA801;
    address alice = vm.addr(ALICE_PK);
    address bob = vm.addr(BOB_PK);
    address carol = vm.addr(CAROL_PK);

    address admin = address(0xAD);
    address resolver = address(0x9E50);
    address arbiter = address(0xA8);
    address treasury = address(0x77);
    address owner = address(0x1010);
    address pauser = address(0x2020);
    address builderClaimer = address(0xB1D);
    bytes32 builderTag = bytes32(uint256(uint160(address(0xB1D))));

    uint64 constant RESOLUTION_DEADLINE_OFFSET = 1 hours;
    uint32 constant CHALLENGE_WINDOW = 30 minutes;
    uint256 constant BOND = 100;

    function setUp() public {
        usdc = new MockUSDC();
        mt = new MockMessageTransmitterV2(address(usdc));

        // Deploy RefundProtocolFixed via UUPS proxy
        RefundProtocolFixed escrowImpl = new RefundProtocolFixed();
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(escrowImpl),
            abi.encodeCall(
                RefundProtocolFixed.initialize,
                (arbiter, address(usdc), "RefundProtocolFixed", "1", owner, pauser)
            )
        );
        escrow = RefundProtocolFixed(address(escrowProxy));

        // Deploy Operator via UUPS proxy
        Operator opImpl = new Operator();
        ERC1967Proxy opProxy = new ERC1967Proxy(
            address(opImpl),
            abi.encodeCall(
                Operator.initialize,
                (admin, address(escrow), treasury, BOND, address(mt), address(usdc), "Operator", "1", owner, pauser)
            )
        );
        op = Operator(address(opProxy));

        usdc.mint(alice, 1_000_000);
        usdc.mint(bob, 1_000_000);
        usdc.mint(carol, 1_000_000);

        vm.prank(alice); usdc.approve(address(op), type(uint256).max);
        vm.prank(bob); usdc.approve(address(op), type(uint256).max);
        vm.prank(carol); usdc.approve(address(op), type(uint256).max);
    }

    // ---------- createMarket ----------

    function test_createMarket_byAdmin_succeeds() public {
        vm.prank(admin);
        uint256 mid = op.createMarket(
            keccak256("CPI > 3.2% in April"),
            IERC20(address(usdc)),
            resolver,
            uint64(block.timestamp + RESOLUTION_DEADLINE_OFFSET),
            CHALLENGE_WINDOW
        );
        assertEq(mid, 0);
        assertEq(op.marketCount(), 1);
        (, IERC20 token, address r,,,, Operator.State state,,) = op.markets(0);
        assertEq(address(token), address(usdc));
        assertEq(r, resolver);
        assertEq(uint256(state), uint256(Operator.State.Open));
    }

    function test_createMarket_byNonAdmin_reverts() public {
        vm.prank(alice);
        vm.expectRevert(Operator.NotAdmin.selector);
        op.createMarket(bytes32(0), IERC20(address(usdc)), resolver, uint64(block.timestamp + 1 hours), CHALLENGE_WINDOW);
    }

    // ---------- matchOrders ----------

    function test_matchOrders_complementary_settlesCollateralAndShares() public {
        uint256 mid = _createDefaultMarket();
        // Alice buys YES @ 0.6, Bob buys NO @ 0.4. fillSize 100.
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory sigYes = _sign(yes, ALICE_PK);
        bytes memory sigNo = _sign(no, BOB_PK);

        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        uint256 bobUSDCBefore = usdc.balanceOf(bob);

        op.matchOrders(yes, sigYes, no, sigNo, 100);

        assertEq(aliceUSDCBefore - usdc.balanceOf(alice), 60, "alice paid 0.6 * 100 = 60");
        assertEq(bobUSDCBefore - usdc.balanceOf(bob), 40, "bob paid 0.4 * 100 = 40");
        assertEq(op.shares(mid, alice, 0), 100);
        assertEq(op.shares(mid, bob, 1), 100);
        assertEq(usdc.balanceOf(address(op)), 100);
    }

    function test_matchOrders_priceMismatch_reverts() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 5_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory sy = _sign(yes, ALICE_PK);
        bytes memory sn = _sign(no, BOB_PK);
        vm.expectRevert(Operator.PriceMismatch.selector);
        op.matchOrders(yes, sy, no, sn, 100);
    }

    function test_matchOrders_outcomeMismatch_reverts() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 1, 6_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory sy = _sign(yes, ALICE_PK);
        bytes memory sn = _sign(no, BOB_PK);
        vm.expectRevert(Operator.OutcomeMismatch.selector);
        op.matchOrders(yes, sy, no, sn, 100);
    }

    function test_matchOrders_invalidSig_reverts() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory wrongSig = _sign(yes, BOB_PK); // Bob signing Alice's order
        bytes memory sn = _sign(no, BOB_PK);
        vm.expectRevert(Operator.InvalidSignature.selector);
        op.matchOrders(yes, wrongSig, no, sn, 100);
    }

    function test_matchOrders_overfill_reverts() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 5_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 5_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory sy = _sign(yes, ALICE_PK);
        bytes memory sn = _sign(no, BOB_PK);
        vm.expectRevert(Operator.OrderOverfilled.selector);
        op.matchOrders(yes, sy, no, sn, 101);
    }

    function test_matchOrders_partialThenFull() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 5_000, 100, 0, bytes32(0), 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 5_000, 100, 0, bytes32(0), 2, block.timestamp + 1 hours);
        bytes memory sy = _sign(yes, ALICE_PK);
        bytes memory sn = _sign(no, BOB_PK);

        op.matchOrders(yes, sy, no, sn, 30);
        op.matchOrders(yes, sy, no, sn, 70);

        assertEq(op.shares(mid, alice, 0), 100);
        assertEq(op.shares(mid, bob, 1), 100);
        assertEq(op.orderFilled(op.hashOrder(yes)), 100);
    }

    function test_matchOrders_accruesBuilderFees() public {
        uint256 mid = _createDefaultMarket();
        // 100 bps fee on each side, fillSize 10_000 so fee math lands above the integer floor.
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 10_000, 100, builderTag, 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 10_000, 100, builderTag, 2, block.timestamp + 1 hours);

        op.matchOrders(yes, _sign(yes, ALICE_PK), no, _sign(no, BOB_PK), 10_000);

        // yesCost 6_000 * 100 bps = 60, noCost 4_000 * 100 bps = 40, total fee 100.
        assertEq(op.builderFees(builderTag, address(usdc)), 100);
    }

    // ---------- proposeResolution / settle / redeem ----------

    function test_proposeResolution_byNonResolver_reverts() public {
        uint256 mid = _createDefaultMarket();
        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(alice);
        vm.expectRevert(Operator.NotResolver.selector);
        op.proposeResolution(mid, 0);
    }

    function test_proposeResolution_beforeDeadline_reverts() public {
        uint256 mid = _createDefaultMarket();
        vm.prank(resolver);
        vm.expectRevert(Operator.ResolutionDeadlineNotReached.selector);
        op.proposeResolution(mid, 0);
    }

    function test_settle_afterChallengeWindow_finalizes() public {
        uint256 mid = _createDefaultMarket();
        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(resolver);
        op.proposeResolution(mid, 0);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        op.settle(mid);
        (,,,,,, Operator.State state,,) = op.markets(mid);
        assertEq(uint256(state), uint256(Operator.State.Settled));
    }

    function test_settle_beforeChallengeWindow_reverts() public {
        uint256 mid = _createDefaultMarket();
        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(resolver);
        op.proposeResolution(mid, 0);
        vm.expectRevert(Operator.ChallengeWindowOpen.selector);
        op.settle(mid);
    }

    function test_redeem_winningHolderGetsCollateral() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 100, 0, bytes32(0), 1, block.timestamp + 2 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 100, 0, bytes32(0), 2, block.timestamp + 2 hours);
        op.matchOrders(yes, _sign(yes, ALICE_PK), no, _sign(no, BOB_PK), 100);

        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(resolver);
        op.proposeResolution(mid, 0); // YES wins
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        op.settle(mid);

        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        op.redeem(mid);
        assertEq(usdc.balanceOf(alice) - aliceUSDCBefore, 100, "YES holder receives 1 unit per share");
        assertEq(op.shares(mid, alice, 0), 0);

        // Bob has 100 NO shares, wins nothing
        uint256 bobUSDCBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        op.redeem(mid);
        assertEq(usdc.balanceOf(bob) - bobUSDCBefore, 0);
    }

    // ---------- dispute path ----------

    function test_challengeResolution_postsBondToEscrow() public {
        uint256 mid = _createDefaultMarket();
        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(resolver);
        op.proposeResolution(mid, 0);

        uint256 carolBefore = usdc.balanceOf(carol);
        vm.prank(carol);
        op.challengeResolution(mid);
        assertEq(carolBefore - usdc.balanceOf(carol), BOND, "challenger debits bond");

        (,,,,,, Operator.State state,,) = op.markets(mid);
        assertEq(uint256(state), uint256(Operator.State.Disputed));
        assertEq(op.disputeChallenger(mid), carol);

        // bond is in the escrow as a payment from operator (recipient = carol, refundTo = treasury)
        uint256 paymentId = op.disputePaymentId(mid);
        (address to, uint256 amount,, address refundTo,, bool refunded) = escrow.payments(paymentId);
        assertEq(to, carol);
        assertEq(amount, BOND);
        assertEq(refundTo, treasury);
        assertFalse(refunded);
    }

    function test_arbiterFinalizeDispute_challengerLost_bondRefundsToTreasury() public {
        uint256 mid = _setupChallengedMarket();
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        // Production pattern: arbiter atomically batches both calls (multisig safe-tx).
        // Test: same vm.prank(arbiter) wraps both.
        vm.startPrank(arbiter);
        op.arbiterFinalizeDispute(mid, 0, false); // resolution stands, challenger loses
        escrow.refundByArbiter(op.disputePaymentId(mid));
        vm.stopPrank();

        assertEq(usdc.balanceOf(treasury) - treasuryBefore, BOND, "bond refunded to treasury");
        (,,,,,, Operator.State state, uint8 win,) = op.markets(mid);
        assertEq(uint256(state), uint256(Operator.State.Settled));
        assertEq(win, 0);
    }

    function test_arbiterFinalizeDispute_challengerWon_bondStaysInEscrow() public {
        uint256 mid = _setupChallengedMarket();
        uint256 carolEscrowBalBefore = escrow.balances(carol);

        vm.prank(arbiter);
        op.arbiterFinalizeDispute(mid, 1, true); // resolution flips, challenger wins

        // carol's escrow balance is the bond, still locked until lockup elapses
        assertEq(escrow.balances(carol), carolEscrowBalBefore, "no immediate movement");
        (,,,,,, Operator.State state, uint8 win,) = op.markets(mid);
        assertEq(uint256(state), uint256(Operator.State.Settled));
        assertEq(win, 1);
    }

    function test_arbiterFinalizeDispute_byNonArbiter_reverts() public {
        uint256 mid = _setupChallengedMarket();
        vm.prank(alice);
        vm.expectRevert(Operator.NotArbiter.selector);
        op.arbiterFinalizeDispute(mid, 0, false);
    }

    // ---------- builder fees ----------

    function test_withdrawBuilderFees_byClaimer_succeeds() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 10_000, 100, builderTag, 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 10_000, 100, builderTag, 2, block.timestamp + 1 hours);
        op.matchOrders(yes, _sign(yes, ALICE_PK), no, _sign(no, BOB_PK), 10_000);
        assertEq(op.builderFees(builderTag, address(usdc)), 100);

        // builderTag's low-160 bits == builderClaimer
        vm.prank(builderClaimer);
        op.withdrawBuilderFees(builderTag, IERC20(address(usdc)), builderClaimer);
        assertEq(usdc.balanceOf(builderClaimer), 100);
        assertEq(op.builderFees(builderTag, address(usdc)), 0);
    }

    function test_withdrawBuilderFees_byOther_reverts() public {
        uint256 mid = _createDefaultMarket();
        Operator.Order memory yes = _order(alice, mid, 0, 6_000, 10_000, 100, builderTag, 1, block.timestamp + 1 hours);
        Operator.Order memory no = _order(bob, mid, 1, 4_000, 10_000, 100, builderTag, 2, block.timestamp + 1 hours);
        op.matchOrders(yes, _sign(yes, ALICE_PK), no, _sign(no, BOB_PK), 10_000);

        vm.prank(alice);
        vm.expectRevert(Operator.NotAdmin.selector);
        op.withdrawBuilderFees(builderTag, IERC20(address(usdc)), alice);
    }

    // ---------- helpers ----------

    function _createDefaultMarket() internal returns (uint256 mid) {
        vm.prank(admin);
        mid = op.createMarket(
            keccak256("test market"),
            IERC20(address(usdc)),
            resolver,
            uint64(block.timestamp + RESOLUTION_DEADLINE_OFFSET),
            CHALLENGE_WINDOW
        );
    }

    function _setupChallengedMarket() internal returns (uint256 mid) {
        mid = _createDefaultMarket();
        vm.warp(block.timestamp + RESOLUTION_DEADLINE_OFFSET + 1);
        vm.prank(resolver);
        op.proposeResolution(mid, 0);
        vm.prank(carol);
        op.challengeResolution(mid);
    }

    function _order(
        address maker,
        uint256 marketId,
        uint8 outcome,
        uint256 price,
        uint256 size,
        uint256 feeBps,
        bytes32 builder,
        uint256 salt,
        uint256 expiry
    ) internal pure returns (Operator.Order memory o) {
        o = Operator.Order({
            maker: maker,
            marketId: marketId,
            outcome: outcome,
            price: price,
            size: size,
            feeBps: feeBps,
            builder: builder,
            salt: salt,
            expiry: expiry
        });
    }

    function _sign(Operator.Order memory o, uint256 pk) internal view returns (bytes memory) {
        bytes32 h = op.hashOrder(o);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, h);
        return abi.encodePacked(r, s, v);
    }

    // ---------- CCTP receive (M1) ----------

    function test_cctpReceive_creditsFollowerMatchedShares() public {
        // Create a USDC-settled market.
        vm.prank(admin);
        uint256 mid = op.createMarket(
            keccak256("CPI > 3.2%"),
            IERC20(address(usdc)),
            resolver,
            uint64(block.timestamp + RESOLUTION_DEADLINE_OFFSET),
            CHALLENGE_WINDOW
        );

        // Configure the mock CCTP transmitter to mint 1000 USDC on receive.
        uint256 amount = 1_000 * 1e6;
        mt.setMintAmount(amount);

        // Payload encodes (follower, marketId) at the CCTP v2 hook offset (376 bytes in).
        bytes memory payload = abi.encode(carol, mid);
        bytes memory message = bytes.concat(new bytes(376), payload);

        op.onCCTPReceive(message, "");

        // Carol receives matched YES + NO shares equal to mintedAmount; market totalCollateral
        // increased by the same.
        assertEq(op.shares(mid, carol, 0), amount);
        assertEq(op.shares(mid, carol, 1), amount);
        (,,,,,,,, uint256 totalCollateral) = op.markets(mid);
        assertEq(totalCollateral, amount);
        assertEq(usdc.balanceOf(address(op)), amount);
    }

    function test_cctpReceive_noopsForUnknownMarketId() public {
        // No markets created; market id 999 does not exist.
        mt.setMintAmount(500 * 1e6);
        bytes memory payload = abi.encode(carol, uint256(999));
        bytes memory message = bytes.concat(new bytes(376), payload);

        op.onCCTPReceive(message, "");

        // Mint still happened (transmitter side), but no shares credited and totalCollateral
        // for the (non-existent) market is unchanged.
        assertEq(op.shares(999, carol, 0), 0);
        assertEq(op.shares(999, carol, 1), 0);
        // USDC was still credited to the Operator (sticky deposit; admin could sweep later).
        assertEq(usdc.balanceOf(address(op)), 500 * 1e6);
    }
}
