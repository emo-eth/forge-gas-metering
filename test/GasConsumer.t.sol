// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Test} from "forge-std/Test.sol";
import {GasConsumer} from "../src/GasConsumer.sol";

contract GasConsumerTest is GasConsumer, Test {
    uint256 constant CONSUME_MAX_DELTA = 38;

    function testConsume(uint32 gasToUse) public {
        address invalidAddress = INVALID_ADDRESS;
        uint256 codeSize;
        bytes memory code = new bytes(1);
        assembly {
            codeSize := extcodesize(invalidAddress)
            extcodecopy(invalidAddress, add(code, 0x20), 0, 1)
        }
        assertEq(codeSize, 1);
        assertEq(code[0], hex"FE");

        // initializeGasConsumer();
        gasToUse =
            uint32(bound(gasToUse, CONSUME_OVERHEAD + 1, type(uint24).max));
        uint256 startingGas = gasleft();
        consumeGas(gasToUse);
        uint256 afterGasUsed = gasleft();
        uint256 gasUsed = startingGas - afterGasUsed;
        assertApproxEqAbs(
            gasToUse, gasUsed, CONSUME_MAX_DELTA, "gasToUse != gasUsed"
        );
        emit log_named_uint(
            "difference",
            (gasUsed > gasToUse) ? gasUsed - gasToUse : gasToUse - gasUsed
        );
    }

    // function testBurn(uint32 gasToUse) public {
    //     gasToUse = uint32(bound(gasToUse, 0, type(uint24).max));
    //     uint256 startingGas = gasleft();
    //     burn(gasToUse);
    //     uint256 afterGasUsed = gasleft();
    //     uint256 gasUsed = startingGas - afterGasUsed;
    //     assertApproxEqAbs(gasToUse, gasUsed, 331, "gasToUse != gasUsed");
    //     emit log_named_uint(
    //         "difference",
    //         (gasUsed > gasToUse) ? gasUsed - gasToUse : gasToUse - gasUsed
    //     );
    // }

    // function burn(uint256 amount) internal view {
    //     uint256 i;
    //     uint256 initialGas = gasleft();
    //     while (initialGas - gasleft() < amount) {
    //         ++i;
    //     }
    // }
}
