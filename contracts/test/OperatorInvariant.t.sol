// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RefundProtocolFixed} from "@reverbprotocol/protocol/RefundProtocolFixed.sol";
import {Operator} from "../src/Operator.sol";

contract InvUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract OperatorStateHandler is Test {
    Operator public op;
    IERC20 public settlement;
    address public admin;
    address public resolver;
    uint256 public marketCreateCount;

    constructor(Operator _op, IERC20 _settlement, address _admin, address _resolver) {
        op = _op;
        settlement = _settlement;
        admin = _admin;
        resolver = _resolver;
    }

    function createMarket(uint64 deadlineDelta, uint32 challengeWindow) external {
        deadlineDelta = uint64(bound(deadlineDelta, 1, 100_000));
        challengeWindow = uint32(bound(challengeWindow, 1, 10_000));
        vm.prank(admin);
        op.createMarket(
            keccak256(abi.encode(marketCreateCount)),
            settlement,
            resolver,
            uint64(block.timestamp) + deadlineDelta,
            challengeWindow
        );
        marketCreateCount++;
    }
}

contract OperatorInvariantTest is Test {
    RefundProtocolFixed public escrow;
    Operator public op;
    InvUSDC public usdc;

    address public arbiter = address(0xA);
    address public admin = address(0xAD);
    address public resolver = address(0x9E50);
    address public treasury = address(0x77);
    address public owner = address(0x10);
    address public pauser = address(0x20);

    /// @dev Snapshot of market state at any time the invariant runs; once any market is observed
    ///      Settled, it must remain Settled or Cancelled forever.
    mapping(uint256 => bool) public wasSettled;

    function setUp() public {
        usdc = new InvUSDC();

        RefundProtocolFixed escrowImpl = new RefundProtocolFixed();
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(escrowImpl),
            abi.encodeCall(
                RefundProtocolFixed.initialize,
                (arbiter, address(usdc), "Esc", "1", owner, pauser)
            )
        );
        escrow = RefundProtocolFixed(address(escrowProxy));

        Operator opImpl = new Operator();
        ERC1967Proxy opProxy = new ERC1967Proxy(
            address(opImpl),
            abi.encodeCall(
                Operator.initialize,
                (admin, address(escrow), treasury, 100, address(0xDEAD), address(usdc), "Op", "1", owner, pauser)
            )
        );
        op = Operator(address(opProxy));

        // Seed one market so the handler has a settlementToken to copy.
        vm.prank(admin);
        op.createMarket(keccak256("seed"), usdc, resolver, uint64(block.timestamp + 1 hours), 30 minutes);

        OperatorStateHandler handler = new OperatorStateHandler(op, IERC20(address(usdc)), admin, resolver);
        targetContract(address(handler));
    }

    /// @notice The Initializable lock holds: re-calling initialize after deploy reverts.
    function invariant_initializerOnlyOnce() public {
        vm.expectRevert();
        op.initialize(admin, address(escrow), treasury, 100, address(0xDEAD), address(usdc), "Op", "1", owner, pauser);
    }

    /// @notice The owner is the configured owner address (Timelock in production) at all times.
    ///         Upgrade authority can only transfer via the Ownable transferOwnership path, which
    ///         is itself onlyOwner. The handler has no path to call transferOwnership.
    function invariant_ownerRemainsTimelock() public view {
        assertEq(op.owner(), owner);
    }
}
