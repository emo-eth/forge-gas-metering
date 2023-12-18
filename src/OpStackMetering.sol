// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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
    uint256 constant L1_OVERHEAD = 188;

    function getCallOverhead(TransactionData memory data)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 callDataCosts = callDataCost(data.callData);
        uint256 l1Costs = 188 + 1792 + callDataCosts;
        console2.log(
            string.concat(
                "~L1 Gas cost     : ",
                LibString.toString(l1Costs),
                " gas (before), ",
                LibString.toString(l1Costs * L1_FEE_SCALAR_BPS / 10_000),
                " gas (after scalar multiplier)"
            )
        );
        console2.log(
            string.concat(
                "~L1 Gas breakdown: 188 (constant) + ~1792 (RLP) + ",
                LibString.toString(callDataCosts),
                " (calldata)"
            )
        );
        return super.getCallOverhead(data);
    }
}
