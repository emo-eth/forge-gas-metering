// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Metering} from "./Metering.sol";
import {NetworkTxCosts, AccessCosts} from "./Structs.sol";
import {
    MAINNET_CALLDATA_ZERO_BYTE_COST,
    MAINNET_CALLDATA_NON_ZERO_BYTE_COST,
    MAINNET_FLAT_TX_COST,
    MAINNET_ACCESS_LIST_ADDRESS_COST,
    MAINNET_ACCESS_LIST_STORAGE_KEY_COST,
    MAINNET_BASE_ACCESS_COST,
    MAINNET_COST_COLD_ACCOUNT_ACCESS,
    MAINNET_COST_COLD_SLOAD,
    MAINNET_COST_COLD_SSTORE,
    MAINNET_COST_SSTORE_CHANGE_ORIGINAL_ZERO,
    MAINNET_COST_SSTORE_CHANGE_ORIGINAL_NON_ZERO,
    MAINNET_COST_SSTORE_CHANGE_NON_ORIGINAL,
    MAINNET_COST_INITIALIZE_ACCOUNT,
    MAINNET_REFUND_RESTORE_NON_ZERO_SLOT_TO_ZERO,
    MAINNET_REFUND_TEMP_ZERO_TO_NON_ZERO,
    MAINNET_REFUND_NON_ZERO_TO_ZERO,
    MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_WARM,
    MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_COLD,
    MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_WARM,
    MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_COLD,
    MAINNET_MAX_REFUND_DENOMINATOR
} from "./Constants.sol";

/**
 * @title MainnetMetering
 * @author emo.eth
 * @notice Gas metering utils configured for Ethereum mainnet.
 */
contract MainnetMetering is
    Metering(
        NetworkTxCosts({
            calldataZeroByteCost: MAINNET_CALLDATA_ZERO_BYTE_COST,
            calldataNonZeroByteCost: MAINNET_CALLDATA_NON_ZERO_BYTE_COST,
            flatTxCost: MAINNET_FLAT_TX_COST,
            accessListAddressCost: MAINNET_ACCESS_LIST_ADDRESS_COST,
            accessListStorageKeyCost: MAINNET_ACCESS_LIST_STORAGE_KEY_COST,
            maxRefundDenominator: MAINNET_MAX_REFUND_DENOMINATOR
        }),
        AccessCosts({
            baseAccessCost: MAINNET_BASE_ACCESS_COST,
            costColdAccountAccess: MAINNET_COST_COLD_ACCOUNT_ACCESS,
            costColdSload: MAINNET_COST_COLD_SLOAD,
            costColdSstore: MAINNET_COST_COLD_SSTORE,
            costSstoreChangeOriginalZero: MAINNET_COST_SSTORE_CHANGE_ORIGINAL_ZERO,
            costSstoreChangeOriginalNonZero: MAINNET_COST_SSTORE_CHANGE_ORIGINAL_NON_ZERO,
            costSstoreChangeNonOriginal: MAINNET_COST_SSTORE_CHANGE_NON_ORIGINAL,
            costInitializeAccount: MAINNET_COST_INITIALIZE_ACCOUNT,
            refundRestoreNonZeroSlotToZero: MAINNET_REFUND_RESTORE_NON_ZERO_SLOT_TO_ZERO,
            refundTempZeroToNonZero: MAINNET_REFUND_TEMP_ZERO_TO_NON_ZERO,
            refundNonZeroToZero: MAINNET_REFUND_NON_ZERO_TO_ZERO,
            refundRestoreTempNonZeroToZeroWarm: MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_WARM,
            refundRestoreTempNonZeroToZeroCold: MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_COLD,
            refundRestoreOriginalNonZeroWarm: MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_WARM,
            refundRestoreOriginalNonZeroCold: MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_COLD
        })
    )
{}
