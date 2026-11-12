// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Disperse
/// @notice Pays many recipients one ERC-20 in a single transaction.
/// @dev Funds move straight from the caller to each recipient with `transferFrom`; the contract never
///      holds tokens, has no owner, no fee, no pause and no upgrade path. Reentrancy cannot move anything
///      the caller did not already approve, so there is no guard. Fee-on-transfer and rebasing tokens are
///      not supported: recipients would receive less than `amounts[i]` and nothing here detects it.
contract Disperse {
    using SafeERC20 for IERC20;

    error LengthMismatch();
    error Empty();
    error ZeroRecipient(uint256 index);
    /// @dev Paying this contract or the token itself would lock the funds forever (no rescue path).
    error SelfRecipient(uint256 index);
    error ZeroAmount(uint256 index);
    error InsufficientAllowance(uint256 needed, uint256 have);

    /// @notice One per call. Per-recipient detail is in the token's own `Transfer` logs.
    event Dispersed(address indexed sender, address indexed token, uint256 total, uint256 count);

    /// @notice Sends `amounts[i]` of `token` from the caller to `to[i]` for every i.
    /// @dev Requires a prior approval of at least the sum of `amounts`.
    function disperse(IERC20 token, address[] calldata to, uint256[] calldata amounts) external {
        uint256 total = _validate(to, amounts);
        _requireAllowance(token, total);
        _transferAll(token, to, amounts, total);
    }

    /// @notice Same as `disperse`, with an EIP-2612 permit for exactly the sum of `amounts`.
    /// @dev The permit call is wrapped so a front-run permit (someone replaying the signature first) cannot
    ///      block the send: if `permit` reverts but the allowance is already sufficient, the send proceeds.
    ///      If the allowance is short, the permit's own revert reason is bubbled up so an expired deadline,
    ///      wrong domain or bad signature is reported as such instead of as a bare allowance shortfall.
    function disperseWithPermit(
        IERC20 token,
        address[] calldata to,
        uint256[] calldata amounts,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        uint256 total = _validate(to, amounts);
        try IERC20Permit(address(token)).permit(msg.sender, address(this), total, deadline, v, r, s) {}
        catch (bytes memory reason) {
            if (token.allowance(msg.sender, address(this)) < total) {
                if (reason.length == 0) {
                    revert InsufficientAllowance(total, token.allowance(msg.sender, address(this)));
                }
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        _requireAllowance(token, total);
        _transferAll(token, to, amounts, total);
    }

    /// @notice Sum of `amounts`, after the same checks `disperse` applies. Reverts on invalid input.
    function sumOf(address[] calldata to, uint256[] calldata amounts) external view returns (uint256) {
        return _validate(to, amounts);
    }

    function _validate(address[] calldata to, uint256[] calldata amounts) private view returns (uint256 sum) {
        uint256 n = to.length;
        if (n == 0) revert Empty();
        if (n != amounts.length) revert LengthMismatch();
        for (uint256 i; i < n; ++i) {
            if (to[i] == address(0)) revert ZeroRecipient(i);
            if (to[i] == address(this)) revert SelfRecipient(i);
            if (amounts[i] == 0) revert ZeroAmount(i);
            sum += amounts[i];
        }
    }

    function _requireAllowance(IERC20 token, uint256 needed) private view {
        uint256 have = token.allowance(msg.sender, address(this));
        if (have < needed) revert InsufficientAllowance(needed, have);
    }

    function _transferAll(IERC20 token, address[] calldata to, uint256[] calldata amounts, uint256 sum) private {
        uint256 n = to.length;
        for (uint256 i; i < n; ++i) {
            token.safeTransferFrom(msg.sender, to[i], amounts[i]);
        }
        emit Dispersed(msg.sender, address(token), sum, n);
    }
}
