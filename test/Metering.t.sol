// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Test} from "forge-std/Test.sol";
import {MainnetMetering} from "../src/MainnetMetering.sol";
import {TestERC20} from "./helpers/TestERC20.sol";
import {TokenTransferrer} from "./helpers/TokenTransferrer.sol";
import {Writer} from "./Writer.sol";

contract MeteringTest is MainnetMetering, Test {
    uint256 thing;
    TestERC20 token1;
    TestERC20 token2;
    TokenTransferrer transferrer;
    int256 warmStorageTest;
    Writer writer;

    function setUp() public {
        setUpMetering({verbose: false});
        token1 = new TestERC20();
        token2 = new TestERC20();
        transferrer = new TokenTransferrer();
        warmStorageTest = 1;
        writer = new Writer();
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

    function testManualMetering() public manuallyMetered {
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

    function testMeteringRealWorldErc20M() public manuallyMetered {
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

    function testWarmStorage() public {
        vm.resumeGasMetering();
        warmStorageTest = 2;
    }

    function testCallData() public {
        bytes memory cd =
            hex"646174613a6170706c69636174696f6e2f6a736f6e2c7b2270223a22626173652d3230222c226f70223a2270726f78795f7472616e73666572222c2270726f7879223a5b7b227469636b223a2262617365222c226e6f6e6365223a2231373032353037373933353833222c2266726f6d223a22307836383965313937663264373236653165353361393136356636316362386366663563316431643963222c22746f223a22307833626461643864633331626561303661666432386434343931663130316535623665303239336134222c22616d74223a223130303030222c2276616c7565223a22302e3237222c227369676e223a22307832356432623066343032643563303336666639366231316636663939346334366539343433616538616662303466646232383531633762633834303765383864343134386365383863653763383561396162376439356334643562386639323036323935653836373232666663626431313833333938623635633464666439313163227d5d7d";
        uint256 cost = callDataCost(cd);
        emit log_named_uint("cost", cost);
    }

    function testCheatcodeWarmth() public manuallyMetered {
        vm.load({target: address(writer), slot: bytes32(0)});
        meterCallAndLog({
            from: address(0),
            to: address(writer),
            value: 0,
            callData: abi.encodeCall(Writer.read, (bytes32(0))),
            transaction: true,
            expectRevert: false,
            message: "Writer.read"
        });
    }
}
