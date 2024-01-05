// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract TokenTransferrer {
    function spend(address erc20, address from, address to, uint256 amount)
        public
    {
        IERC20(erc20).transferFrom(from, to, amount);
    }
}
