// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {MainnetMetering} from "../src/MainnetMetering.sol";

contract MeteringTest is MainnetMetering {
    uint256 thing;

    function setUp() public {
        // vm.pauseGasMetering();
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

    function testManualMetering() public manualMetering {
        meterCallAndLog({
            to: address(0x123456),
            callData: hex"000001",
            value: 0,
            transaction: true,
            message: "manual"
        });
    }
}
