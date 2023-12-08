// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

/**
 * @title TemperatureAccounting
 * @author emo.eth
 * @notice Helpers for manually accounting for gas accounting differences based
 *         on account and temperature "warmth."
 *         TODO: use immutables to allow configuring for different networks and
 *         hard forks.
 */
contract TemperatureAccounting is Test {
    bytes32 immutable TEMPERATURE_ACCOUNTING_SLOT =
        keccak256("TemperatureAccounting");
    uint256 immutable COST_DIFF_COLD_ACCOUNT_ACCESS = 2500; // 2600 - 100 = 2500
    uint256 immutable COST_DIFF_COLD_SLOAD = 2000; // 2100 - 100 = 2100
    uint256 immutable COST_DIFF_DIRTY_WRITE; //
    uint256 immutable COST_DIFF_WARM_WRITE_DIFF;
    uint256 immutable REFUND_RESTORE_SLOT_ORIGINAL_VALUE;
    uint256 immutable REFUND_RESTORE_SLOT_ZERO_VALUE;
    uint256 immutable REFUND_DELETE_SLOT;

    struct GasMeasurements {
        uint256 evmGas;
        uint256 adjustedGas;
        int256 evmRefund;
        int256 adjustedRefund;
    }

    struct TemperatureStorage {
        uint256 index;
    }

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

    struct SlotTemperatureMapping {
        mapping(address account => AccountStatus status) accountStatus;
        mapping(
            address account => mapping(bytes32 slot => SlotStatus slotStatus)
            ) slotStatus;
    }

    function getSlotMap()
        internal
        view
        returns (SlotTemperatureMapping storage)
    {
        TemperatureStorage storage tempSlot;
        bytes32 slot = TEMPERATURE_ACCOUNTING_SLOT;
        SlotTemperatureMapping storage slotMap;
        assembly {
            tempSlot.slot := slot
            mstore(0x00, sload(slot))
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
        SlotTemperatureMapping storage slotMap = getSlotMap();
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
        SlotTemperatureMapping storage slotMap = getSlotMap();
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

    function processAccountAccesses(Vm.AccountAccess[] memory accesses)
        public
        returns (GasMeasurements memory measurements)
    {
        uint256 evmGas;
        uint256 adjustedGas;
        int256 evmRefund;
        int256 adjustedRefund;
        for (uint256 i; i < accesses.length; ++i) {
            (
                uint256 evmGas_,
                uint256 adjustedGas_,
                int256 evmRefund_,
                int256 adjustedRefund_
            ) = processAccountAccess(accesses[i]);
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
    function processAccountAccess(Vm.AccountAccess memory access)
        public
        returns (
            uint256 evmGas,
            uint256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        SlotTemperatureMapping storage slotMap = getSlotMap();
        address accessedAccount = access.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];

        evmGas = adjustedGas = 100;

        if (
            (accountStatus.needsWarmAdjustment || !accountStatus.isWarm)
                && !isPrecompile(access.account)
        ) {
            if (
                !(
                    access.kind == VmSafe.AccountAccessKind.Create
                        || access.kind == VmSafe.AccountAccessKind.SelfDestruct
                        || access.kind == VmSafe.AccountAccessKind.Resume
                )
            ) {
                // TODO: account for initialized status
                adjustedGas += COST_DIFF_COLD_ACCOUNT_ACCESS;
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
        Vm.StorageAccess[] memory storageAccesses = access.storageAccesses;
        for (uint256 i; i < storageAccesses.length; ++i) {
            (
                uint256 slotEvmGas,
                uint256 slotAdjustedGas,
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
            uint256 evmGas,
            uint256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        SlotTemperatureMapping storage slotMap = getSlotMap();
        address accessedAccount = access.account;
        bytes32 accessedSlot = access.slot;
        SlotStatus storage slotStatus =
            slotMap.slotStatus[accessedAccount][accessedSlot];
        // if doing an SLOAD, just account for the cold surcharge, and do nothing with refunds
        if (!access.isWrite) {
            evmGas = adjustedGas = 100;
            if (slotStatus.needsWarmAdjustment || !slotStatus.isWarm) {
                adjustedGas += COST_DIFF_COLD_SLOAD;
                if (!access.reverted) {
                    slotStatus.needsWarmAdjustment = false;
                    slotStatus.isWarm = true;
                }
            }
        } else {
            // for SSTOREs, calculate both the gas and refund for both the EVM state and the idealized test state

            // use helper to get original values, as they may not have been recorded during preprocessing of test setup
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
    ) public pure returns (uint256 baseDynamicGas, int256 gasRefund) {
        return (
            calcSstoreBaseDynamicGas(
                warm, originalValue, currentValue, newValue
                ),
            calcSstoreGasRefund(warm, originalValue, currentValue, newValue)
        );
    }

    function calcSstoreBaseDynamicGas(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) public pure returns (uint256 baseDynamicGas) {
        if (newValue == currentValue) {
            if (warm) {
                baseDynamicGas = 100; // COST_WARM_SSTORE_SAME_VALUE;
            } else {
                baseDynamicGas = 100; // COST_COLD_SSTORE_SAME_VALUE;
            }
        } else if (currentValue == originalValue) {
            if (originalValue == 0) {
                baseDynamicGas = 20000; // COST_SSTORE_CHANGE_ORIGINAL_ZERO;
            } else {
                baseDynamicGas = 2900; // COST_SSTORE_CHANGE_ORIGINAL_NONZERO;
            }
        } else {
            baseDynamicGas = 100; // COST_SSTORE_CHANGE_NONORIGINAL;
        }
        baseDynamicGas += (warm) ? 0 : 2100; // COST_SSTORE_COLD_ACCESS;
    }

    function calcSstoreGasRefund(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) public pure returns (int256 gasRefund) {
        if (newValue != currentValue) {
            if (currentValue == originalValue) {
                if (originalValue != 0 && newValue == 0) {
                    gasRefund += 4800; // REFUND_RESTORE_SLOT_NONZERO;
                }
            } else if (originalValue != 0) {
                if (currentValue == 0) {
                    gasRefund -= 4800; // REFUND_DIRTY_TRANSIENT_ZERO;
                } else if (newValue == 0) {
                    gasRefund += 4800; // REFUND_CLEAR_DIRTY_SLOT;
                }
            }
        }
        if (newValue == originalValue) {
            if (originalValue == 0) {
                if (warm) {
                    gasRefund += 20000 - 100; // REFUND_WARM_RESTORE_SLOT_ORIGINAL_VALUE_ZERO;
                } else {
                    gasRefund += 19900; // REFUND_COLD_RESTORE_SLOT_ORIGINAL_VALUE_ZERO;
                }
            } else {
                if (warm) {
                    gasRefund += 5000 - 2100 - 100; // REFUND_WARM_RESTORE_SLOT_ORIGINAL_VALUE_NONZERO;
                } else {
                    gasRefund += 4900; // REFUND_COLD_RESTORE_SLOT_ORIGINAL_VALUE_NONZERO;
                }
            }
        }
    }

    function isPrecompile(address account) public pure returns (bool) {
        return account < address(10) && account > address(0);
    }
}
