// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

struct MeterCallArgs {
    address from;
    address to;
    bytes callData;
    uint256 value;
    bool transaction;
    bool expectRevert;
    string message;
}

struct AccessListEntry {
    address account;
    bytes32[] storageKeys;
}

struct TransactionData {
    address to;
    bytes callData;
    AccessListEntry[] accessListEntries;
}

struct NetworkTxCosts {
    uint256 calldataZeroByteCost;
    uint256 calldataNonZeroByteCost;
    uint256 flatTxCost;
    uint256 accessListAddressCost;
    uint256 accessListStorageKeyCost;
    uint256 maxRefundDenominator;
}

struct AccessCosts {
    int256 baseAccessCost;
    int256 costColdAccountAccess;
    // int256 costCallPositiveValue; // in practice this shouldn't be affected by Foundry test execution
    int256 costColdSload;
    int256 costColdSstore;
    int256 costSstoreChangeOriginalZero;
    int256 costSstoreChangeOriginalNonZero;
    int256 costSstoreChangeNonOriginal;
    int256 costInitializeAccount;
    int256 refundRestoreNonZeroSlotToZero;
    int256 refundTempZeroToNonZero;
    int256 refundNonZeroToZero;
    int256 refundRestoreTempNonZeroToZeroWarm;
    int256 refundRestoreTempNonZeroToZeroCold;
    int256 refundRestoreOriginalNonZeroWarm;
    int256 refundRestoreOriginalNonZeroCold;
}

struct GasMeasurements {
    int256 evmGas;
    int256 adjustedGas;
    int256 evmRefund;
    int256 adjustedRefund;
}
