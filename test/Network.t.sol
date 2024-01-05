// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {DSTest} from "ds-test/test.sol";
import {Test} from "forge-std/Test.sol";

contract NetworkTest is DSTest {
    function testNothing() public {
        assertEq(uint256(1), uint256(1));
        emit log_named_uint("hi", uint256(1));
    }

    function testNothingFuzz(uint256 x) public {
        assertEq(x, x);
        emit log_named_uint("hi", uint256(1));
    }
}

contract Network2Test is Test {
    function testNothing() public {
        assertEq(uint256(1), uint256(1));
        emit log_named_uint("hi", uint256(1));
    }

    function testNothingFuzz(uint256 x) public {
        assertEq(x, x);
        emit log_named_uint("hi", uint256(1));
    }
}
