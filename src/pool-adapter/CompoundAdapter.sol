// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IPoolAdapter } from "pwn/interfaces/IPoolAdapter.sol";
import { AddressMissingHubTag } from "pwn/PWNErrors.sol";

import { checkInputs } from "src/pool-adapter/utils/checkInputs.sol";


interface ICometLike {
    function allow(address manager, bool isAllowed) external;

    function supply(address asset, uint amount) external;
    function supplyFrom(address from, address dst, address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;
    function withdrawFrom(address src, address to, address asset, uint amount) external;
}

contract CompoundAdapter is IPoolAdapter {
    using MultiToken for MultiToken.Asset;
    using MultiToken for address;

    PWNHub public immutable hub;

    error HubZeroAddress();

    constructor(address _hub) {
        if (_hub == address(0)) {
            revert HubZeroAddress();
        }

        hub = PWNHub(_hub);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function withdraw(address pool, address owner, address asset, uint256 amount) external {
        checkInputs(pool, owner, asset, amount);

        // Check caller is active loan contract
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: msg.sender, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Withdraw from the pool to the owner
        ICometLike(pool).withdrawFrom(owner, owner, asset, amount);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function supply(address pool, address owner, address asset, uint256 amount) external {
        checkInputs(pool, owner, asset, amount);

        // Supply to the pool on behalf of the owner
        asset.ERC20(amount).approveAsset(pool);
        ICometLike(pool).supplyFrom(address(this), owner, asset, amount);
    }

}
