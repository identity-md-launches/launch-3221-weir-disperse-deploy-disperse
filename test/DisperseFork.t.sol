// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Disperse} from "../src/Disperse.sol";

interface IPermitToken is IERC20, IERC20Permit {}

/// @dev Runs only when RH_RPC_URL is set. Exercises the real tokens the Weir app pays prizes in on Robinhood
///      Chain (4663): USDG (Paxos Global Dollar, 6 decimals, EIP-2612 permit) and WEIR (18 decimals, no permit).
contract DisperseForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant WEIR = 0x58b82fa656ECF47a0dca5bE6BAd06B92E22f7dbE;

    Disperse internal d;
    IPermitToken internal usdg = IPermitToken(USDG);
    IERC20 internal weir = IERC20(WEIR);
    uint256 internal senderKey = 0xBA5E;
    address internal sender;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        assertEq(block.chainid, 4663, "RH_RPC_URL is not Robinhood Chain");
        d = new Disperse();
        sender = vm.addr(senderKey);
        deal(USDG, sender, 100_000e6);
        deal(WEIR, sender, 100_000e18);
    }

    modifier onFork() {
        if (address(d) == address(0)) {
            vm.skip(true);
        }
        _;
    }

    function test_fork_usdgPermitDisperse() public onFork {
        address[] memory to = new address[](3);
        uint256[] memory amts = new uint256[](3);
        to[0] = makeAddr("r1");
        to[1] = makeAddr("r2");
        to[2] = makeAddr("r3");
        amts[0] = 1_000e6;
        amts[1] = 2_500e6;
        amts[2] = 1;
        uint256 total = 3_500e6 + 1;
        uint256 deadline = block.timestamp + 20 minutes;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                sender,
                address(d),
                total,
                usdg.nonces(sender),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdg.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderKey, digest);

        vm.prank(sender);
        d.disperseWithPermit(usdg, to, amts, deadline, v, r, s);

        assertEq(usdg.balanceOf(to[0]), 1_000e6);
        assertEq(usdg.balanceOf(to[1]), 2_500e6);
        assertEq(usdg.balanceOf(to[2]), 1);
        assertEq(usdg.balanceOf(sender), 100_000e6 - total);
        assertEq(usdg.allowance(sender, address(d)), 0);
    }

    function test_fork_usdgApproveDisperse() public onFork {
        address[] memory to = new address[](1);
        uint256[] memory amts = new uint256[](1);
        to[0] = makeAddr("r1");
        amts[0] = 42e6;
        vm.startPrank(sender);
        usdg.approve(address(d), 42e6);
        d.disperse(usdg, to, amts);
        vm.stopPrank();
        assertEq(usdg.balanceOf(to[0]), 42e6);
    }

    /// @dev WEIR has no permit: approve first, and each recipient gets exactly amounts[i] (no transfer fee).
    function test_fork_weirApproveDisperse() public onFork {
        address[] memory to = new address[](2);
        uint256[] memory amts = new uint256[](2);
        to[0] = makeAddr("w1");
        to[1] = makeAddr("w2");
        amts[0] = 10_000e18;
        amts[1] = 1;
        vm.startPrank(sender);
        weir.approve(address(d), 10_000e18 + 1);
        d.disperse(weir, to, amts);
        vm.stopPrank();
        assertEq(weir.balanceOf(to[0]), 10_000e18);
        assertEq(weir.balanceOf(to[1]), 1);
        assertEq(weir.balanceOf(sender), 100_000e18 - 10_000e18 - 1);
    }

    /// @dev WEIR without permit through disperseWithPermit: zeros for the signature, allowance is the gate.
    function test_fork_weirPermitPathFallsBackToAllowance() public onFork {
        address[] memory to = new address[](1);
        uint256[] memory amts = new uint256[](1);
        to[0] = makeAddr("w1");
        amts[0] = 5e18;
        vm.startPrank(sender);
        weir.approve(address(d), 5e18);
        d.disperseWithPermit(weir, to, amts, 0, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
        assertEq(weir.balanceOf(to[0]), 5e18);
    }

    /// @dev Real-token execution gas per fresh-balance recipient, scaled to the app's cap of 250 per transaction.
    ///      A sample of 40 keeps the fork's storage reads few enough for a public (non-archive) RPC.
    function test_fork_gasPerRecipient_250fit() public onFork {
        uint256 n = 40;
        address[] memory to = new address[](n);
        uint256[] memory amts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            to[i] = address(uint160(uint256(keccak256(abi.encode("fresh", i)))));
            amts[i] = 1e6;
        }
        vm.startPrank(sender);
        usdg.approve(address(d), n * 1e6);
        uint256 g = gasleft();
        d.disperse(usdg, to, amts);
        g -= gasleft();
        vm.stopPrank();
        uint256 per = g / n;
        emit log_named_uint("real USDG gas per fresh recipient", per);
        assertLt(per * 250 + 200_000, 16_000_000, "250 recipients must stay well under a 32M per-tx gas limit");
    }
}
