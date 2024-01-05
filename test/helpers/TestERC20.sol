// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {ERC20} from "solady/tokens/ERC20.sol";

contract TestERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "TestERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "TST";
    }

    function deal(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
