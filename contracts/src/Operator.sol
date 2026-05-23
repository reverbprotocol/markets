// SPDX-License-Identifier: Apache-2.0
/*
 * Copyright 2026 project-reverb
 * Licensed under the Apache License, Version 2.0.
 *
 * Binary prediction-market operator. Two-sided EIP-712 orderbook with builder-bytes32
 * attribution per fill. Dispute path routes a challenger bond through RefundProtocolFixed
 * (sibling contract in this workspace).
 */

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";

contract Operator is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum State { Open, ResolutionProposed, Disputed, Settled, Cancelled }

    // Dispute state transitions follow two structural shapes:
    //   - Chargeback dispute lifecycle (card-network shape):
    //     acquirer-initiated complaint -> issuer review -> arbiter ruling -> enforcement.
    //     Maps onto: proposeResolution -> challengeResolution -> arbiterFinalizeDispute -> settle/redeem.
    //   - Institutional arbitration framework: mediation -> binding ruling -> enforcement.
    //     Maps onto: the challenge window itself is the mediation step (no ruling required if
    //     the parties allow the proposed resolution to stand); arbiterFinalizeDispute is the
    //     binding ruling; on-chain settlement plus bond movement is the enforcement.
    // The on-chain surface stays minimal so the off-chain procedural overlay can mirror
    // whichever framework the deploying institution operates inside.

    struct Market {
        bytes32 questionHash;
        IERC20 settlementToken;
        address resolver;
        uint64 resolutionDeadline;
        uint32 challengeWindowSeconds;
        uint64 proposedAt;
        State state;
        uint8 winningOutcome;
        uint256 totalCollateral;
    }

    struct Order {
        address maker;
        uint256 marketId;
        uint8 outcome;       // 0 = YES, 1 = NO
        uint256 price;       // basis points of PRICE_DENOM (10_000)
        uint256 size;        // total order size in shares
        uint256 feeBps;      // builder fee in basis points of fill collateral
        bytes32 builder;
        uint256 salt;
        uint256 expiry;
    }

    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,uint256 marketId,uint8 outcome,uint256 price,uint256 size,uint256 feeBps,bytes32 builder,uint256 salt,uint256 expiry)"
    );

    uint256 public constant PRICE_DENOM = 10_000;
    uint256 public constant FEE_DENOM = 10_000;
    uint256 public constant MAX_FEE_BPS = 200; // 2% per side hard cap

    RefundProtocolFixed public immutable disputeEscrow;
    address public immutable admin;
    uint256 public immutable challengeBond;
    address public immutable treasury;

    uint256 public marketCount;
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => mapping(uint8 => uint256))) public shares;
    mapping(bytes32 => uint256) public orderFilled;
    mapping(bytes32 => mapping(address => uint256)) public builderFees;
    mapping(uint256 => uint256) public disputePaymentId;
    mapping(uint256 => address) public disputeChallenger;

    event MarketCreated(
        uint256 indexed marketId,
        bytes32 indexed questionHash,
        address indexed settlementToken,
        address resolver,
        uint64 resolutionDeadline,
        uint32 challengeWindowSeconds
    );
    event OrderFilled(
        bytes32 indexed yesOrderHash,
        bytes32 indexed noOrderHash,
        uint256 indexed marketId,
        address yesMaker,
        address noMaker,
        uint256 fillSize,
        uint256 yesPrice,
        uint256 noPrice,
        bytes32 yesBuilder,
        bytes32 noBuilder
    );
    event BuilderFeeAccrued(bytes32 indexed builder, address indexed token, uint256 amount);
    event BuilderFeeWithdrawn(bytes32 indexed builder, address indexed token, address to, uint256 amount);
    event ResolutionProposed(uint256 indexed marketId, uint8 winningOutcome, uint64 challengeDeadline);
    event ResolutionChallenged(uint256 indexed marketId, address indexed challenger, uint256 paymentId);
    event DisputeFinalized(uint256 indexed marketId, uint8 finalOutcome, bool challengerWon);
    event MarketSettled(uint256 indexed marketId, uint8 winningOutcome);
    event Redeemed(uint256 indexed marketId, address indexed holder, uint256 amount);

    error NotAdmin();
    error NotResolver();
    error NotArbiter();
    error InvalidState();
    error InvalidOutcome();
    error InvalidPrice();
    error InvalidFee();
    error PriceMismatch();
    error MarketMismatch();
    error OutcomeMismatch();
    error OrderExpired();
    error OrderOverfilled();
    error InvalidSignature();
    error ZeroAddress();
    error ZeroSize();
    error ChallengeWindowOpen();
    error ChallengeWindowClosed();
    error ResolutionDeadlineNotReached();

    constructor(
        address _admin,
        RefundProtocolFixed _disputeEscrow,
        address _treasury,
        uint256 _challengeBond,
        string memory eip712Name,
        string memory eip712Version
    ) EIP712(eip712Name, eip712Version) {
        if (_admin == address(0) || address(_disputeEscrow) == address(0) || _treasury == address(0)) revert ZeroAddress();
        admin = _admin;
        disputeEscrow = _disputeEscrow;
        treasury = _treasury;
        challengeBond = _challengeBond;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function createMarket(
        bytes32 questionHash,
        IERC20 settlementToken,
        address resolver,
        uint64 resolutionDeadline,
        uint32 challengeWindowSeconds
    ) external onlyAdmin returns (uint256 marketId) {
        if (address(settlementToken) == address(0) || resolver == address(0)) revert ZeroAddress();
        marketId = marketCount;
        markets[marketId] = Market({
            questionHash: questionHash,
            settlementToken: settlementToken,
            resolver: resolver,
            resolutionDeadline: resolutionDeadline,
            challengeWindowSeconds: challengeWindowSeconds,
            proposedAt: 0,
            state: State.Open,
            winningOutcome: 0,
            totalCollateral: 0
        });
        unchecked { marketCount = marketId + 1; }
        emit MarketCreated(marketId, questionHash, address(settlementToken), resolver, resolutionDeadline, challengeWindowSeconds);
    }

    function hashOrder(Order calldata o) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                o.maker,
                o.marketId,
                o.outcome,
                o.price,
                o.size,
                o.feeBps,
                o.builder,
                o.salt,
                o.expiry
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function matchOrders(
        Order calldata yesOrder,
        bytes calldata yesSig,
        Order calldata noOrder,
        bytes calldata noSig,
        uint256 fillSize
    ) external nonReentrant {
        if (fillSize == 0) revert ZeroSize();
        if (yesOrder.outcome != 0 || noOrder.outcome != 1) revert OutcomeMismatch();
        if (yesOrder.marketId != noOrder.marketId) revert MarketMismatch();
        if (yesOrder.price + noOrder.price != PRICE_DENOM) revert PriceMismatch();
        if (yesOrder.feeBps > MAX_FEE_BPS || noOrder.feeBps > MAX_FEE_BPS) revert InvalidFee();
        if (block.timestamp > yesOrder.expiry || block.timestamp > noOrder.expiry) revert OrderExpired();

        Market storage m = markets[yesOrder.marketId];
        if (m.state != State.Open) revert InvalidState();

        bytes32 yesHash = hashOrder(yesOrder);
        bytes32 noHash = hashOrder(noOrder);

        if (ECDSA.recover(yesHash, yesSig) != yesOrder.maker) revert InvalidSignature();
        if (ECDSA.recover(noHash, noSig) != noOrder.maker) revert InvalidSignature();

        uint256 yesAlready = orderFilled[yesHash];
        uint256 noAlready = orderFilled[noHash];
        if (yesAlready + fillSize > yesOrder.size) revert OrderOverfilled();
        if (noAlready + fillSize > noOrder.size) revert OrderOverfilled();
        orderFilled[yesHash] = yesAlready + fillSize;
        orderFilled[noHash] = noAlready + fillSize;

        uint256 yesCost = (fillSize * yesOrder.price) / PRICE_DENOM;
        uint256 noCost = (fillSize * noOrder.price) / PRICE_DENOM;
        // rounding: any leftover goes to noCost so total == fillSize
        uint256 fillNotional = fillSize;
        if (yesCost + noCost != fillNotional) {
            noCost = fillNotional - yesCost;
        }

        m.settlementToken.safeTransferFrom(yesOrder.maker, address(this), yesCost);
        m.settlementToken.safeTransferFrom(noOrder.maker, address(this), noCost);

        m.totalCollateral += fillNotional;
        shares[yesOrder.marketId][yesOrder.maker][0] += fillSize;
        shares[noOrder.marketId][noOrder.maker][1] += fillSize;

        // Builder fee accrual: feeBps applied to that side's notional, debited from settled collateral.
        // The fee comes out of the operator's accumulated pool (so winners receive payouts net of fees on their side).
        if (yesOrder.feeBps > 0 && yesOrder.builder != bytes32(0)) {
            uint256 feeY = (yesCost * yesOrder.feeBps) / FEE_DENOM;
            builderFees[yesOrder.builder][address(m.settlementToken)] += feeY;
            emit BuilderFeeAccrued(yesOrder.builder, address(m.settlementToken), feeY);
        }
        if (noOrder.feeBps > 0 && noOrder.builder != bytes32(0)) {
            uint256 feeN = (noCost * noOrder.feeBps) / FEE_DENOM;
            builderFees[noOrder.builder][address(m.settlementToken)] += feeN;
            emit BuilderFeeAccrued(noOrder.builder, address(m.settlementToken), feeN);
        }

        emit OrderFilled(
            yesHash,
            noHash,
            yesOrder.marketId,
            yesOrder.maker,
            noOrder.maker,
            fillSize,
            yesOrder.price,
            noOrder.price,
            yesOrder.builder,
            noOrder.builder
        );
    }

    function proposeResolution(uint256 marketId, uint8 winningOutcome) external {
        Market storage m = markets[marketId];
        if (msg.sender != m.resolver) revert NotResolver();
        if (m.state != State.Open) revert InvalidState();
        if (block.timestamp < m.resolutionDeadline) revert ResolutionDeadlineNotReached();
        if (winningOutcome > 1) revert InvalidOutcome();
        m.winningOutcome = winningOutcome;
        m.proposedAt = uint64(block.timestamp);
        m.state = State.ResolutionProposed;
        emit ResolutionProposed(marketId, winningOutcome, uint64(block.timestamp) + m.challengeWindowSeconds);
    }

    function challengeResolution(uint256 marketId) external nonReentrant {
        Market storage m = markets[marketId];
        if (m.state != State.ResolutionProposed) revert InvalidState();
        if (block.timestamp >= uint256(m.proposedAt) + m.challengeWindowSeconds) revert ChallengeWindowClosed();

        // Pull bond from challenger.
        m.settlementToken.safeTransferFrom(msg.sender, address(this), challengeBond);
        // Approve and route into the dispute escrow as a payment to challenger,
        // refunding to treasury if arbiter rules against challenger.
        m.settlementToken.forceApprove(address(disputeEscrow), challengeBond);

        uint256 paymentIdBefore = disputeEscrow.nonce();
        disputeEscrow.pay(msg.sender, challengeBond, treasury);
        // payment id is whatever nonce was before the pay() call
        disputePaymentId[marketId] = paymentIdBefore;
        disputeChallenger[marketId] = msg.sender;
        m.state = State.Disputed;

        emit ResolutionChallenged(marketId, msg.sender, paymentIdBefore);
    }

    /**
     * Arbiter-only finalization. The arbiter is `disputeEscrow.arbiter()`; the same address
     * arbitrates the bond escrow and the market resolution by construction.
     *
     * This call updates only the operator-side market state. The bond movement on the escrow
     * is a separate transaction the same arbiter must issue against the escrow contract:
     *   - `challengerWon = false`: arbiter calls `escrow.refundByArbiter(disputePaymentId(marketId))`
     *     to send the bond back to `treasury`.
     *   - `challengerWon = true`: arbiter takes no action on the escrow; the bond remains
     *     locked under the challenger's name and the challenger calls `escrow.withdraw([id])`
     *     once the lockup elapses.
     *
     * The two-call pattern is intentional. In production the arbiter is a multisig that batches
     * both calls into a single safe-transaction. The contract surfaces remain orthogonal:
     * operator owns market state, escrow owns bond custody.
     */
    function arbiterFinalizeDispute(uint256 marketId, uint8 finalOutcome, bool challengerWon) external nonReentrant {
        Market storage m = markets[marketId];
        if (msg.sender != disputeEscrow.arbiter()) revert NotArbiter();
        if (m.state != State.Disputed) revert InvalidState();
        if (finalOutcome > 1) revert InvalidOutcome();

        m.winningOutcome = finalOutcome;
        m.state = State.Settled;
        emit DisputeFinalized(marketId, finalOutcome, challengerWon);
        emit MarketSettled(marketId, finalOutcome);
    }

    function settle(uint256 marketId) external {
        Market storage m = markets[marketId];
        if (m.state != State.ResolutionProposed) revert InvalidState();
        if (block.timestamp < uint256(m.proposedAt) + m.challengeWindowSeconds) revert ChallengeWindowOpen();
        m.state = State.Settled;
        emit MarketSettled(marketId, m.winningOutcome);
    }

    function redeem(uint256 marketId) external nonReentrant {
        Market storage m = markets[marketId];
        if (m.state != State.Settled) revert InvalidState();
        uint256 winShares = shares[marketId][msg.sender][m.winningOutcome];
        if (winShares == 0) return;
        shares[marketId][msg.sender][m.winningOutcome] = 0;
        m.settlementToken.safeTransfer(msg.sender, winShares);
        emit Redeemed(marketId, msg.sender, winShares);
    }

    function withdrawBuilderFees(bytes32 builder, IERC20 token, address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        // Only the address with the builder bytes32 secret can claim. For a hackathon-grade contract,
        // we treat the builder bytes32 as a public-key tag and require msg.sender to match its low-160 bits.
        // A production contract would use a registry mapping bytes32 -> claimer.
        address claimer = address(uint160(uint256(builder)));
        if (msg.sender != claimer) revert NotAdmin();
        uint256 amount = builderFees[builder][address(token)];
        if (amount == 0) return;
        builderFees[builder][address(token)] = 0;
        token.safeTransfer(to, amount);
        emit BuilderFeeWithdrawn(builder, address(token), to, amount);
    }
}
