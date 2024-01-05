// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {MainnetMetering} from "./MainnetMetering.sol";
import {NetworkTxCosts, AccessCosts, TransactionData} from "./Structs.sol";
import {console2} from "forge-std/console2.sol";
import {LibString} from "solady/utils/LibString.sol";

/**
 * @title OpStackMetering
 * @author emo.eth
 * @notice Gas metering utils configured for Op-Stack.
 */
contract OpStackMetering is MainnetMetering {
    // todo: read these values from op-mainnet contract
    uint256 constant L1_FEE_SCALAR_BPS = 6840;
    uint256 constant BPS_DENOM = 10_000;
    uint256 constant L1_OVERHEAD = 188;
    uint256 constant L1_RLP_OVERHEAD = 112 * 16; // assume ~112 bytes; 16 gas per byte

    function getCallOverhead(TransactionData memory data)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 callDataCosts = callDataCost(data.callData);
        uint256 l1Costs = L1_OVERHEAD + L1_RLP_OVERHEAD + callDataCosts;
        console2.log(
            string.concat(
                "~L1 Gas breakdown: ",
                LibString.toString(L1_OVERHEAD),
                " (constant) + ~",
                LibString.toString(L1_RLP_OVERHEAD),
                " (RLP) + ",
                LibString.toString(callDataCosts),
                " (calldata)"
            )
        );
        console2.log(
            string.concat(
                "~L1 Gas cost     : ",
                LibString.toString(l1Costs),
                " gas (before), ",
                LibString.toString(l1Costs * L1_FEE_SCALAR_BPS / BPS_DENOM),
                " gas (after scalar multiplier)"
            )
        );

        return super.getCallOverhead(data);
    }
}
