// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC-20 without permit, standing in for bridged USDC.e.
contract PlainToken is ERC20 {
    constructor() ERC20("Bridged USDC", "USDC.e") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
