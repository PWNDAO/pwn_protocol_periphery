// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IPoolAdapter } from "pwn/interfaces/IPoolAdapter.sol";
import { AddressMissingHubTag } from "pwn/PWNErrors.sol";


interface IERC4626Like {
    function asset() external view returns (address);

    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}

contract ERC4626Adapter is IPoolAdapter {
    using MultiToken for MultiToken.Asset;
    using MultiToken for address;

    PWNHub public hub;

    error InvalidVaultAsset(address creditAsset, address vaultAsset);

    constructor(address _hub) {
        hub = PWNHub(_hub);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function withdraw(address vault, address owner, address asset, uint256 amount) external {
        // Check caller is active loan contract
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: msg.sender, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check the asset of the vault
        address vaultAsset = IERC4626Like(vault).asset();
        if (vaultAsset != asset) {
            revert InvalidVaultAsset(asset, vaultAsset);
        }

        // Note: Performing optimistic withdraw, assuming that the vault will revert if the amount is not available
        // Withdraw from the vault to the owner
        IERC4626Like(vault).withdraw(amount, owner, owner);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function supply(address vault, address owner, address asset, uint256 amount) external {
        // Check the asset of the vault
        address vaultAsset = IERC4626Like(vault).asset();
        if (vaultAsset != asset) {
            revert InvalidVaultAsset(asset, vaultAsset);
        }

        // Note: Performing optimistic deposit, assuming that the vault will revert if the amount exceeds the max deposit
        // Supply to the vault on behalf of the owner
        asset.ERC20(amount).approveAsset(vault);
        IERC4626Like(vault).deposit(amount, owner);
    }

}
