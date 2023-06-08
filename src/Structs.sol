// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct AccessListEntry {
    address account;
    bytes32[] storageKeys;
}

struct TransactionData {
    address to;
    bytes callData;
    AccessListEntry[] accessListEntries;
}
