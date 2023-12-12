// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {MainnetMetering} from "../src/MainnetMetering.sol";
import {TestERC20} from "./helpers/TestERC20.sol";
import {TokenTransferrer} from "./helpers/TokenTransferrer.sol";

contract MeteringTest is MainnetMetering {
    uint256 thing;
    TestERC20 token1;
    TestERC20 token2;
    TokenTransferrer transferrer;

    function setUp() public {
        setUpMetering({verbose: true});
        token1 = new TestERC20();
        token2 = new TestERC20();
        transferrer = new TokenTransferrer();
    }

    function testCalldataCosts() public {
        vm.resumeGasMetering();
        uint256 singleZeroCost = getCallOverhead(address(0x12345), hex"00");
        uint256 singleNonZeroCost = getCallOverhead(address(0x12345), hex"01");
        assertEq(
            singleZeroCost,
            CALLDATA_ZERO_BYTE_COST + FLAT_TX_COST,
            "singleZeroCost"
        );
        assertEq(
            singleNonZeroCost,
            CALLDATA_NON_ZERO_BYTE_COST + FLAT_TX_COST,
            "singleNonZeroCost"
        );
    }

    function testManualMetering() public {
        meterCallAndLog({
            to: address(0x123456),
            callData: hex"000001",
            value: 0,
            transaction: true,
            message: "manual"
        });

        vm.resumeGasMetering();
    }

    function testRealWorldErc20() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        token1.deal(alice, 100);
        token1.deal(address(makeAddr("bob")), 100);
        // token2.deal(alice, 200);
        // token2.deal(address(makeAddr("bob")), 200);
        vm.startPrank(alice);
        token1.approve(address(transferrer), type(uint256).max);
        // vm.startPrank(bob);
        // token2.approve(address(transferrer), 200);
        bytes memory callData = abi.encodeCall(
            TokenTransferrer.spend, (address(token1), alice, bob, 100)
        );
        meterCallAndLog({
            to: address(transferrer),
            callData: callData,
            value: 0,
            transaction: true,
            message: "spend"
        });
        vm.resumeGasMetering();
        // transferrer.spend(address(token1), alice, bob, 99);
    }
}
