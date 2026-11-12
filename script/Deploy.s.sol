// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Disperse} from "../src/Disperse.sol";

/// @dev Deterministic deploy through the CREATE2 proxy at 0x4e59b44847b379578588920cA78FbF26c0B4956C
///      (forge uses it automatically when a salt is given). Same salt + same bytecode = same address on
///      every chain. Change SALT only if the bytecode changes and a fresh address is wanted.
contract Deploy is Script {
    bytes32 public constant SALT = keccak256("payusdc.disperse.v1");
    /// @dev Pinned so a silent bytecode drift (solc patch, optimizer setting, code change) between the Sepolia
    ///      and Base deploys fails loudly instead of landing at a different address on each chain.
    address public constant EXPECTED = 0x320418D854f3eD0E59e691dD7c767A22B8E5C9E9;

    function run() external {
        require(predict() == EXPECTED, "bytecode drift: predicted address != EXPECTED");
        if (EXPECTED.code.length != 0) {
            console.log("Disperse already deployed at", EXPECTED);
            return;
        }
        vm.startBroadcast();
        Disperse d = new Disperse{salt: SALT}();
        vm.stopBroadcast();
        require(address(d) == EXPECTED, "deployed address != EXPECTED");
        console.log("Disperse deployed at", address(d));
    }

    function predict() public pure returns (address) {
        return vm.computeCreate2Address(SALT, keccak256(type(Disperse).creationCode));
    }
}
