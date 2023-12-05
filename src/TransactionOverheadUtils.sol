// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessListEntry, TransactionData} from "./Structs.sol";

contract TransactionOverheadUtils {
    uint256 immutable CALLDATA_ZERO_BYTE_COST;
    uint256 immutable CALLDATA_NON_ZERO_BYTE_COST;
    uint256 immutable FLAT_TX_COST;
    uint256 immutable ACCESS_LIST_ADDRESS_COST;
    uint256 immutable ACCESS_LIST_STORAGE_KEY_COST;

    constructor(
        uint256 calldataZeroByteCost,
        uint256 calldataNonZeroByteCost,
        uint256 flatTxCost,
        uint256 accessListAddressCost,
        uint256 accessListStorageKeyCost
    ) {
        CALLDATA_ZERO_BYTE_COST = calldataZeroByteCost;
        CALLDATA_NON_ZERO_BYTE_COST = calldataNonZeroByteCost;
        FLAT_TX_COST = flatTxCost;
        ACCESS_LIST_ADDRESS_COST = accessListAddressCost;
        ACCESS_LIST_STORAGE_KEY_COST = accessListStorageKeyCost;
    }

    function getCallOverhead(address to, bytes memory callData)
        internal
        view
        returns (uint256)
    {
        AccessListEntry[] memory entries;
        return getCallOverhead(TransactionData(to, callData, entries));
    }

    function getCallOverhead(TransactionData memory txData)
        internal
        view
        returns (uint256)
    {
        uint256 cost = FLAT_TX_COST;
        unchecked {
            cost += getAccessListCost(txData.accessListEntries);
            cost += callDataCost(txData.callData);
        }
        return cost;
    }

    function getAccessListCost(AccessListEntry[] memory entries)
        internal
        view
        returns (uint256)
    {
        uint256 cost;
        unchecked {
            cost += entries.length * ACCESS_LIST_ADDRESS_COST;
        }
        for (uint256 i; i < entries.length; ++i) {
            unchecked {
                cost +=
                    entries[i].storageKeys.length * ACCESS_LIST_STORAGE_KEY_COST;
            }
        }
        return cost;
    }

    function callDataCost(bytes memory callData)
        public
        view
        returns (uint256)
    {
        uint256 cost;
        for (uint256 i; i < callData.length;) {
            if (callData[i] == 0) {
                unchecked {
                    cost += CALLDATA_ZERO_BYTE_COST;
                }
            } else {
                unchecked {
                    cost += CALLDATA_NON_ZERO_BYTE_COST;
                }
            }
            unchecked {
                ++i;
            }
        }
        return cost;
    }
}
