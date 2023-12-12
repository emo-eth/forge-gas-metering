// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessListEntry, TransactionData, NetworkTxCosts} from "./Structs.sol";

/**
 * @title TransactionOverheadUtils
 * @author emo.eth
 * @notice Utils for calculating transaction overhead.
 */
contract TransactionOverheadUtils {
    uint256 immutable CALLDATA_ZERO_BYTE_COST;
    uint256 immutable CALLDATA_NON_ZERO_BYTE_COST;
    uint256 immutable FLAT_TX_COST;
    uint256 immutable ACCESS_LIST_ADDRESS_COST;
    uint256 immutable ACCESS_LIST_STORAGE_KEY_COST;

    constructor(NetworkTxCosts memory networkTxCosts) {
        CALLDATA_ZERO_BYTE_COST = networkTxCosts.calldataZeroByteCost;
        CALLDATA_NON_ZERO_BYTE_COST = networkTxCosts.calldataNonZeroByteCost;
        FLAT_TX_COST = networkTxCosts.flatTxCost;
        ACCESS_LIST_ADDRESS_COST = networkTxCosts.accessListAddressCost;
        ACCESS_LIST_STORAGE_KEY_COST = networkTxCosts.accessListStorageKeyCost;
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
        bytes memory transformed = preprocessCalldata(callData);
        uint256 cost;
        for (uint256 i; i < transformed.length;) {
            if (transformed[i] == 0) {
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

    /**
     * @notice Preprocess calldata according to network rules, ie, Arbitrum
     *         first compresses calldata, then charges 4 gas per byte.
     * @param callData The calldata to preprocess.
     */
    function preprocessCalldata(bytes memory callData)
        internal
        pure
        virtual
        returns (bytes memory)
    {
        return callData;
    }
}
