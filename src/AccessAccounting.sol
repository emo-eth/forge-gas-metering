// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AccessCosts, GasMeasurements} from "./Structs.sol";

/**
 * @title AccessAccounting
 * @author emo.eth
 * @notice Helpers for manually accounting for gas accounting differences based
 *         on account and storage slot "warmth."
 *         TODO: Support multiple forks/chainId accounting.
 */
contract AccessAccounting {
    bytes32 immutable ACCESS_ACCOUNTING_SLOT = keccak256("AccessAccounting");
    int256 immutable COST_BASE_ACCESS;
    int256 immutable COST_COLD_ACCOUNT_ACCESS;
    int256 immutable COST_COLD_SLOAD;
    int256 immutable COST_COLD_SSTORE;
    int256 immutable COST_SSTORE_CHANGE_ORIGINAL_ZERO;
    int256 immutable COST_SSTORE_CHANGE_ORIGINAL_NONZERO;
    int256 immutable COST_SSTORE_CHANGE_NONORIGINAL;
    int256 immutable COST_INITIALIZE_ACCOUNT;
    int256 immutable REFUND_RESTORE_NONZERO_SLOT_TO_ZERO;
    int256 immutable REFUND_TEMP_ZERO_TO_NONZERO;
    int256 immutable REFUND_NONZERO_TO_ZERO;
    int256 immutable REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM;
    int256 immutable REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD;
    int256 immutable REFUND_RESTORE_ORIGINAL_NONZERO_WARM;
    int256 immutable REFUND_RESTORE_ORIGINAL_NONZERO_COLD;
    bool seenTarget;

    struct SlotStatus {
        bool needsWarmAdjustment;
        bool seen;
        bool isWarm;
        bytes32 evmOriginalValue;
        bytes32 testOriginalValue;
    }

    struct AccountStatus {
        bool needsWarmAdjustment;
        bool isWarm;
    }

    struct AccessAccountingStorage {
        mapping(address account => AccountStatus status) accountStatus;
        mapping(
            address account => mapping(bytes32 slot => SlotStatus slotStatus)
            ) slotStatus;
    }

    constructor(AccessCosts memory costs) {
        COST_BASE_ACCESS = costs.baseAccessCost;
        COST_COLD_ACCOUNT_ACCESS = costs.costColdAccountAccess;
        COST_COLD_SLOAD = costs.costColdSload;
        COST_COLD_SSTORE = costs.costColdSstore;
        COST_SSTORE_CHANGE_ORIGINAL_ZERO = costs.costSstoreChangeOriginalZero;
        COST_SSTORE_CHANGE_ORIGINAL_NONZERO =
            costs.costSstoreChangeOriginalNonZero;
        COST_SSTORE_CHANGE_NONORIGINAL = costs.costSstoreChangeNonOriginal;
        COST_INITIALIZE_ACCOUNT = costs.costInitializeAccount;
        REFUND_RESTORE_NONZERO_SLOT_TO_ZERO =
            costs.refundRestoreNonZeroSlotToZero;
        REFUND_TEMP_ZERO_TO_NONZERO = costs.refundTempZeroToNonZero;
        REFUND_NONZERO_TO_ZERO = costs.refundNonZeroToZero;
        REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM =
            costs.refundRestoreTempNonZeroToZeroWarm;
        REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD =
            costs.refundRestoreTempNonZeroToZeroCold;
        REFUND_RESTORE_ORIGINAL_NONZERO_WARM =
            costs.refundRestoreOriginalNonZeroWarm;
        REFUND_RESTORE_ORIGINAL_NONZERO_COLD =
            costs.refundRestoreOriginalNonZeroCold;
    }

    /**
     * @notice Get the storage struct for this contract
     */
    function getAccessAccountingStorage()
        internal
        view
        returns (AccessAccountingStorage storage)
    {
        // TODO: support multiple forks by parameterizing this function
        uint256 forkId = 0;
        bytes32 slot = ACCESS_ACCOUNTING_SLOT;
        AccessAccountingStorage storage slotMap;
        assembly {
            mstore(0x00, forkId)
            mstore(0x20, slot)
            slotMap.slot := keccak256(0x00, 0x40)
        }
        return slotMap;
    }

    function preprocessAccesses(Vm.AccountAccess[] memory accesses)
        public
        returns (Vm.AccountAccess[] memory)
    {
        for (uint256 i; i < accesses.length; ++i) {
            preprocessAccess(accesses[i]);
        }
        return accesses;
    }

    function preprocessAccess(Vm.AccountAccess memory access)
        public
        returns (Vm.AccountAccess memory)
    {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];
        if (!isPrecompile(access.account)) {
            accountStatus.needsWarmAdjustment = true;
        }
        Vm.StorageAccess[] memory storageAccesses = access.storageAccesses;
        for (uint256 i; i < storageAccesses.length; ++i) {
            preprocessStorageAccess(storageAccesses[i]);
        }
        return access;
    }

    function preprocessStorageAccess(Vm.StorageAccess memory access) public {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        bytes32 accessedSlot = access.slot;
        SlotStatus storage slotStatus =
            slotMap.slotStatus[accessedAccount][accessedSlot];
        // don't do anything if access was reverted
        if (!access.reverted) {
            if (!slotStatus.seen) {
                slotStatus.needsWarmAdjustment = true;
                slotStatus.seen = true;
                slotStatus.evmOriginalValue = access.previousValue;
            }
            //
            slotStatus.testOriginalValue = access.newValue;
        }
    }

    function getOriginalSlotValue(
        SlotStatus storage slotStatus,
        Vm.StorageAccess memory access,
        bool test
    ) internal returns (bytes32) {
        // if this is the first time the slot has been seen, assume the access.previousValue is also its original value.
        if (!slotStatus.seen) {
            slotStatus.evmOriginalValue = access.previousValue;
            slotStatus.testOriginalValue = access.previousValue;
            slotStatus.seen = true;
        }
        return
            (test) ? slotStatus.testOriginalValue : slotStatus.evmOriginalValue;
    }

    function processAccountAccesses(
        address target,
        Vm.AccountAccess[] memory accesses
    ) public returns (GasMeasurements memory measurements) {
        seenTarget = false;
        int256 evmGas;
        int256 adjustedGas;
        int256 evmRefund;
        int256 adjustedRefund;
        for (uint256 i; i < accesses.length; ++i) {
            (
                int256 evmGas_,
                int256 adjustedGas_,
                int256 evmRefund_,
                int256 adjustedRefund_
            ) = processAccountAccess(target, accesses[i]);
            evmGas += evmGas_;
            adjustedGas += adjustedGas_;
            evmRefund += evmRefund_;
            adjustedRefund += adjustedRefund_;
        }
        return GasMeasurements(evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    /**
     * @notice Process the account-level access, including all storage accesses.
     *
     *         If an account was warmed by set-up, the cold surcharge will added to
     *         extraGas only the first time the account is accessed.
     *         If the access callframe did not revert, the account will be marked as warmed.
     *               Actual and adjusted gas and refunds are calculate separately because of EVM behavior around refunds.
     *               As of London hard fork, the EVM limits refunds to 1/5 tx cost, and only gives refunds for SSTOREs.
     * @param access The account-level access to process, including all storage accesses.
     */
    function processAccountAccess(
        address target,
        Vm.AccountAccess memory access
    )
        public
        returns (
            int256 evmGas,
            int256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];

        if (access.account == target && !seenTarget) {
            seenTarget = true;
            // if this is the first time the target account is accessed,
            // do not charge any gas, since that will be accounted for by the
            // tx-level overhead.
            // todo: make this configurable?
            adjustedGas = 0;
            // however, assume the evm charges standard gas for the call;
            // the difference will be accounted for by the burned makeup gas.
            evmGas = COST_BASE_ACCESS;
            evmGas += (accountStatus.needsWarmAdjustment)
                ? int256(0)
                : COST_COLD_ACCOUNT_ACCESS;
            evmGas += (access.value > 0 && !access.initialized)
                ? COST_INITIALIZE_ACCOUNT
                : int256(0);
            // warm up target account
            accountStatus.needsWarmAdjustment = false;
            accountStatus.isWarm = true;
        } else {
            evmGas = adjustedGas = COST_BASE_ACCESS;

            // call and selfdestruct must pay extra gas for uninitialized accounts
            if (
                (
                    access.kind == VmSafe.AccountAccessKind.Call
                        || access.kind == VmSafe.AccountAccessKind.SelfDestruct
                )
            ) {
                // struct already accounts for whether or not account is initialized, including due to reverts
                if (access.value > 0 && !access.initialized) {
                    adjustedGas += COST_INITIALIZE_ACCOUNT; // COST_UNINITIALIZED_ACCOUNT_SEND_VALUE
                    evmGas += COST_INITIALIZE_ACCOUNT;
                }
            }

            if (
                (accountStatus.needsWarmAdjustment || !accountStatus.isWarm)
                    && !isPrecompile(access.account)
            ) {
                // create and resume do not pay extra gas for cold accounts
                if (
                    !(
                        access.kind == VmSafe.AccountAccessKind.Create
                            || access.kind == VmSafe.AccountAccessKind.Resume
                    )
                ) {
                    adjustedGas += COST_COLD_ACCOUNT_ACCESS;
                    // only add cold surcharge to evmGas if the account was not warmed by set-up
                    evmGas += (accountStatus.needsWarmAdjustment)
                        ? int256(0)
                        : COST_COLD_ACCOUNT_ACCESS;
                }
                // If this is the first time the account is accessed, and the
                // callframe did not revert, or if the account was the target of a
                // CREATE, mark it as warmed and reset needsWarmAdjusment.
                // TODO: technically, only a CREATE from a non-reverted frame should warm the account
                // eg, if a CREATE reverts _within_ a reverting frame, the account should not be warmed (I think)
                if (
                    !access.reverted
                        || access.kind == VmSafe.AccountAccessKind.Create
                ) {
                    accountStatus.needsWarmAdjustment = false;
                    accountStatus.isWarm = true;
                }
            }
        }

        Vm.StorageAccess[] memory storageAccesses = access.storageAccesses;
        for (uint256 i; i < storageAccesses.length; ++i) {
            (
                int256 slotEvmGas,
                int256 slotAdjustedGas,
                int256 slotEvmRefund,
                int256 slotAdjustedRefund
            ) = processStorageAccess(storageAccesses[i]);
            evmGas += slotEvmGas;
            adjustedGas += slotAdjustedGas;
            evmRefund += slotEvmRefund;
            adjustedRefund += slotAdjustedRefund;
        }
        return (evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    /**
     *
     * @param access The storage access to process.
     * @return evmGas The amount of gas actually charged by the EVM for this access.
     * @return adjustedGas The amount of gas that would have been charged by the EVM if the slot were cold and started with its correct value.
     * @return evmRefund The amount of refund actually given by the EVM for this access.
     * @return adjustedRefund The amount of refund that would have been given by the EVM if the slot were cold and started with its correct value.
     */
    function processStorageAccess(Vm.StorageAccess memory access)
        public
        returns (
            int256 evmGas,
            int256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        bytes32 accessedSlot = access.slot;
        SlotStatus storage slotStatus =
            slotMap.slotStatus[accessedAccount][accessedSlot];
        // if doing an SLOAD, just account for the cold surcharge, and do nothing with refunds
        if (!access.isWrite) {
            evmGas = adjustedGas = COST_BASE_ACCESS;
            if (slotStatus.needsWarmAdjustment || !slotStatus.isWarm) {
                adjustedGas += COST_COLD_SLOAD;
                // only add cold surcharge to evmGas if the slot was not warmed by set-up
                evmGas += (slotStatus.needsWarmAdjustment)
                    ? int256(0)
                    : COST_COLD_SLOAD;
                if (!access.reverted) {
                    slotStatus.needsWarmAdjustment = false;
                    slotStatus.isWarm = true;
                }
            }
        } else {
            // for SSTOREs, calculate both the gas and refund for both the EVM state and the idealized test state

            // use helper to get original values, as they may not have been recorded during preprocessing of test setup
            // TODO: support pre-loaded state with forks/vm.loadAllocs etc
            bytes32 evmOriginalValue = getOriginalSlotValue({
                slotStatus: slotStatus,
                access: access,
                test: false
            });
            bytes32 testOriginalValue = getOriginalSlotValue({
                slotStatus: slotStatus,
                access: access,
                test: true
            });
            bool evmWarm = slotStatus.isWarm || slotStatus.needsWarmAdjustment;
            bytes32 currentValue = access.previousValue;
            bytes32 newValue = access.newValue;
            (evmGas, evmRefund) = calcSstoreCost(
                evmWarm, evmOriginalValue, currentValue, newValue
            );
            (adjustedGas, adjustedRefund) = calcSstoreCost(
                slotStatus.isWarm, testOriginalValue, currentValue, newValue
            );
            if (!access.reverted) {
                slotStatus.isWarm = true;
                slotStatus.needsWarmAdjustment = false;
            }
        }
        return (evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    function calcSstoreCost(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) public view returns (int256 baseDynamicGas, int256 gasRefund) {
        return (
            calcSstoreBaseDynamicGas(
                warm, originalValue, currentValue, newValue
                ),
            calcSstoreGasRefund(warm, originalValue, currentValue, newValue)
        );
    }

    /**
     * @notice Calculate the base dynamic gas for an SSTORE. Virtual to allow overriding for different networks and hard forks.
     * @param warm Whether the slot is warm.
     * @param originalValue The original (pre-tx) value of the slot.
     * @param currentValue The current value of the slot.
     * @param newValue The new value of the slot.
     */
    function calcSstoreBaseDynamicGas(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) public view virtual returns (int256 baseDynamicGas) {
        if (newValue == currentValue) {
            if (warm) {
                baseDynamicGas = COST_BASE_ACCESS;
            } else {
                baseDynamicGas = COST_BASE_ACCESS;
            }
        } else if (currentValue == originalValue) {
            if (originalValue == 0) {
                baseDynamicGas = COST_SSTORE_CHANGE_ORIGINAL_ZERO;
            } else {
                baseDynamicGas = COST_SSTORE_CHANGE_ORIGINAL_NONZERO;
            }
        } else {
            baseDynamicGas = COST_SSTORE_CHANGE_NONORIGINAL;
        }
        baseDynamicGas += (warm) ? int256(0) : int256(COST_COLD_SSTORE);
    }

    /**
     * @notice Calculate the gas refund for an SSTORE. Virtual to allow overriding for different networks and hard forks.
     * @param warm Whether the slot is warm.
     * @param originalValue The original (pre-tx) value of the slot.
     * @param currentValue The current value of the slot.
     * @param newValue The new value of the slot.
     */
    function calcSstoreGasRefund(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) public view virtual returns (int256 gasRefund) {
        if (newValue != currentValue) {
            if (currentValue == originalValue) {
                if (originalValue != 0 && newValue == 0) {
                    gasRefund += REFUND_RESTORE_NONZERO_SLOT_TO_ZERO;
                }
            } else if (originalValue != 0) {
                if (currentValue == 0) {
                    gasRefund -= REFUND_TEMP_ZERO_TO_NONZERO;
                } else if (newValue == 0) {
                    gasRefund += REFUND_NONZERO_TO_ZERO;
                }
            }
        }
        if (newValue == originalValue) {
            if (originalValue == 0) {
                if (warm) {
                    gasRefund += REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM;
                } else {
                    gasRefund += REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD;
                }
            } else {
                if (warm) {
                    gasRefund += REFUND_RESTORE_ORIGINAL_NONZERO_WARM;
                } else {
                    gasRefund += REFUND_RESTORE_ORIGINAL_NONZERO_COLD;
                }
            }
        }
    }

    /**
     * @notice Check if an account is a precompile. Override with different logic depending on network and hard fork.
     * @param account The account to check.
     */
    function isPrecompile(address account) public pure virtual returns (bool) {
        return account < address(10) && account > address(0);
    }
}
