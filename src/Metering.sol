// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessListEntry, TransactionData} from "./Structs.sol";
import {Test} from "forge-std/Test.sol";
import {CallOverheadUtils} from "./CallOverheadUtils.sol";
import {GasConsumer} from "./GasConsumer.sol";

contract Metering is CallOverheadUtils, GasConsumer, Test {
    constructor(
        uint256 calldataZeroByteCost,
        uint256 calldataNonZeroByteCost,
        uint256 flatTxCost,
        uint256 accessListAddressCost,
        uint256 accessListStorageKeyCost
    )
        CallOverheadUtils(
            calldataZeroByteCost,
            calldataNonZeroByteCost,
            flatTxCost,
            accessListAddressCost,
            accessListStorageKeyCost
        )
    {}

    /**
     * @notice Pause gas metering at the beginning of a function
     */
    modifier manualMetering() virtual {
        vm.pauseGasMetering();
        _;
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
     * @notice Add approximately gasCost units of gas to Foundry's gas meter
     * @param gasCost The total gas cost to meter
     */
    function meterGas(uint256 gasCost) public metered {
        consumeGas(gasCost);
    }

    function meterCallAndLog(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction,
        string memory message
    ) public {
        uint256 gasUsed = meterCall(to, callData, value, transaction);
        emit log_named_uint(string.concat(message, "gas used:", ":"), gasUsed);
    }

    function meterCall(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction
    ) internal returns (uint256) {
        uint256 overheadGasCost =
            (transaction) ? getCallOverhead(to, callData) : 0;
        uint256 startingGas = gasleft();
        assembly {
            let succ :=
                call(gas(), to, value, add(callData, 0x20), mload(callData), 0, 0)
            // TODO: how will this work with expectRevert?
            if iszero(succ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        uint256 afterGasUsed = gasleft();
        uint256 gasUsed = startingGas - afterGasUsed + overheadGasCost;
        meterGas(gasUsed);
        return gasUsed;
    }

    /**
     * @notice Get the returndata of the last call as a bytes array
     */
    function getReturndata() internal pure returns (bytes memory) {
        uint256 returnDataSize;
        assembly {
            returnDataSize := returndatasize()
        }
        bytes memory returndata = new bytes(returnDataSize);
        assembly {
            returndatacopy(add(returndata, 0x20), 0, returndatasize())
        }
        return returndata;
    }
}
