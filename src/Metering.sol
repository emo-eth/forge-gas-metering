// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessListEntry, TransactionData} from "./Structs.sol";
import {Test} from "forge-std/Test.sol";
import {TransactionOverheadUtils} from "./TransactionOverheadUtils.sol";
import {GasConsumer} from "./GasConsumer.sol";

contract Metering is TransactionOverheadUtils, GasConsumer, Test {
    constructor(
        uint256 calldataZeroByteCost,
        uint256 calldataNonZeroByteCost,
        uint256 flatTxCost,
        uint256 accessListAddressCost,
        uint256 accessListStorageKeyCost
    )
        TransactionOverheadUtils(
            calldataZeroByteCost,
            calldataNonZeroByteCost,
            flatTxCost,
            accessListAddressCost,
            accessListStorageKeyCost
        )
    {}

    /**
     * @notice Pause gas metering at the beginning of a function
     *         Due to forge quirks, requires resuming at the end of the function,
     *         which incurs a ~3100 gas overhead
     */
    modifier manualMetering() virtual {
        vm.pauseGasMetering();
        _;
        vm.resumeGasMetering();
    }

    /**
     * @notice Meter gas consumed by a function, and then pause gas metering
     */
    modifier metered() virtual {
        vm.resumeGasMetering();
        _;
        vm.pauseGasMetering();
    }

    /**
     * @notice Add approximately gasCost units of gas to Foundry's gas meter.
     *         Resumes and then pauses gas metering.
     * @param gasCost The total gas cost to meter
     */
    function meterGas(uint256 gasCost) internal metered {
        consumeGas(gasCost);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm during call.
     *         Explicitly consume the gas cost of the call plus the static overhead when `transaction` is true.
     *         Emits a log with the given message and the gas used.
     *         Assumes paused gas metering.
     * @param to The address to call
     * @param callData The calldata to send
     * @param value The value to send
     * @param transaction Whether or not this should add static overhead for a transaction
     * @param message A message to prepend to the logged gas usage
     */
    function meterCallAndLog(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction,
        string memory message
    ) internal returns (uint256, bytes memory) {
        (uint256 gasUsed, bytes memory data) =
            meterCall(to, callData, value, transaction);
        emit log_named_uint(string.concat(message, " gas used"), gasUsed);
        return (gasUsed, data);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm during call.
     *         Explicitly consume the gas cost of the call plus the static overhead when `transaction` is true.
     *         Assumes paused gas metering.
     * @param to The address to call
     * @param callData The calldata to send
     * @param value The value to send
     * @param transaction Whether or not this should add static overhead for a transaction
     */
    function meterCall(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction
    ) internal returns (uint256, bytes memory) {
        // Calculate static overhead of the call
        uint256 overheadGasCost =
            (transaction) ? getCallOverhead(to, callData) : 0;

        // track evm gas usage
        uint256 startingGas = gasleft();
        uint256 afterGas;
        uint256 returndataSize;
        bool succ;
        assembly ("memory-safe") {
            succ :=
                call(gas(), to, value, add(callData, 0x20), mload(callData), 0, 0)
        }

        // compiler seems to do some weird caching when this is done in assembly
        afterGas = gasleft();

        // revert if call failed or else copy returndata
        assembly ("memory-safe") {
            // TODO: how will this work with expectRevert?
            if iszero(succ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            // copy return data, if any
            returndataSize := returndatasize()
        }
        bytes memory data = new bytes(returndataSize);
        assembly ("memory-safe") {
            returndatacopy(add(data, 0x20), 0, returndatasize())
        }

        // consume gas
        uint256 gasUsed = startingGas - afterGas + overheadGasCost;
        meterGas(gasUsed);
        return (gasUsed, data);
    }
}
