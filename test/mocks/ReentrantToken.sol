// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Disperse} from "../../src/Disperse.sol";

/// @dev On the first transferFrom, re-enters Disperse.disperse with the stored args, as the original sender
///      would (the token is `msg.sender` inside Disperse, so it can only spend its own allowance). Models a
///      hostile token trying to amplify a send.
contract ReentrantToken is ERC20 {
    Disperse public disperse;
    address[] public to;
    uint256[] public amounts;
    bool private entered;
    uint256 public reentered;

    constructor() ERC20("Reentrant", "RNT") {}

    function mint(address a, uint256 amount) external {
        _mint(a, amount);
    }

    function arm(Disperse d, address[] calldata to_, uint256[] calldata amounts_) external {
        disperse = d;
        to = to_;
        amounts = amounts_;
    }

    function transferFrom(address from, address recipient, uint256 amount) public override returns (bool) {
        if (!entered && address(disperse) != address(0)) {
            entered = true;
            // msg.sender here is Disperse; the re-entrant call is made by this token contract, which has
            // no allowance of its own. Swallow its revert so the outer send continues and the test can
            // assert that nothing beyond the sender's own allowance moved.
            reentered++;
            try disperse.disperse(IERC20(address(this)), to, amounts) {} catch {}
        }
        return super.transferFrom(from, recipient, amount);
    }
}
