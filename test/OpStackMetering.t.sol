// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Test} from "forge-std/Test.sol";
import {OpStackMetering} from "../src/OpStackMetering.sol";
import {TestERC20} from "./helpers/TestERC20.sol";
import {TokenTransferrer} from "./helpers/TokenTransferrer.sol";

contract OpStackMeteringTest is OpStackMetering, Test {
    TestERC20 token1;
    TestERC20 token2;
    TokenTransferrer transferrer;

    function setUp() public {
        setUpMetering({verbose: false});
        token1 = new TestERC20();
        token2 = new TestERC20();
        transferrer = new TokenTransferrer();
    }

    function testManualMeteringOp() public manuallyMetered {
        meterCallAndLog({
            from: address(0),
            to: address(0x123456),
            callData: hex"000001",
            value: 0,
            transaction: true,
            expectRevert: false,
            message: "manual"
        });
    }

    function testMeteringRealWorldErc20Op() public manuallyMetered {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        token1.deal(alice, 100);
        token1.deal(address(makeAddr("bob")), 100);
        vm.prank(alice);
        token1.approve(address(transferrer), type(uint256).max);
        bytes memory callData = abi.encodeCall(
            TokenTransferrer.spend, (address(token1), alice, bob, 100)
        );
        meterCallAndLog({
            from: address(0),
            to: address(transferrer),
            callData: callData,
            value: 0,
            transaction: true,
            expectRevert: false,
            message: "spend"
        });
    }
}
