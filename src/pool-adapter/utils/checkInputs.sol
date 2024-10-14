// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

error PoolZeroAddress();
error OwnerZeroAddress();
error AssetZeroAddress();
error AmountZero();

function checkInputs(address pool, address owner, address asset, uint256 amount) pure {
    if (pool == address(0)) {
        revert PoolZeroAddress();
    }
    if (owner == address(0)) {
        revert OwnerZeroAddress();
    }
    if (asset == address(0)) {
        revert AssetZeroAddress();
    }
    if (amount == 0) {
        revert AmountZero();
    }
}
