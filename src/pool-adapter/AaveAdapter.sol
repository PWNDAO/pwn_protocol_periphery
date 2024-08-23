// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IPoolAdapter } from "pwn/interfaces/IPoolAdapter.sol";
import { AddressMissingHubTag } from "pwn/PWNErrors.sol";


interface IAavePoolLike {
    struct ReserveData {
        uint256 reserveConfigurationMap;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    function getReserveData(address asset) external view returns (ReserveData memory);

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

contract AaveAdapter is IPoolAdapter {
    using MultiToken for MultiToken.Asset;
    using MultiToken for address;

    uint256 public constant DEFAULT_MIN_HEALTH_FACTOR = 1.2e18;

    PWNHub public hub;

    mapping(address => uint256) public minHealthFactor;

    error InvalidMinHealthFactor(uint256 minHealthFactor);
    error HealthFactorBelowMin(uint256 minHealthFactor, uint256 healthFactor);

    constructor(address _hub) {
        hub = PWNHub(_hub);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function withdraw(address pool, address owner, address asset, uint256 amount) external {
        // Check caller is active loan contract
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: msg.sender, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Transfer aTokens to this contract
        IAavePoolLike(pool)
            .getReserveData(asset).aTokenAddress
            .ERC20(amount) // Note: Assuming aToken is minted in 1:1 ratio to underlying asset
            .transferAssetFrom(owner, address(this));

        // Check owner health factor
        (,,,,, uint256 healthFactor) = IAavePoolLike(pool).getUserAccountData(owner);
        uint256 _minHealthFactor = minHealthFactor[owner];
        _minHealthFactor = _minHealthFactor == 0 ? DEFAULT_MIN_HEALTH_FACTOR : _minHealthFactor;
        if (healthFactor < _minHealthFactor) {
            revert HealthFactorBelowMin(_minHealthFactor, healthFactor);
        }

        // Withdraw from the pool to the owner
        IAavePoolLike(pool).withdraw(asset, amount, owner);
    }

    /**
     * @inheritdoc IPoolAdapter
     */
    function supply(address pool, address owner, address asset, uint256 amount) external {
        // Supply to the pool on behalf of the owner
        asset.ERC20(amount).approveAsset(pool);
        IAavePoolLike(pool).supply(asset, amount, owner, 0);
    }

    /**
     * @notice Set a minimum health factor that is acceptable after a successful withdrawal.
     * @param _minHealthFactor The new minimum health factor.
     */
    function setMinHealthFactor(uint256 _minHealthFactor) external {
        if (_minHealthFactor < 1e18) {
            revert InvalidMinHealthFactor(_minHealthFactor);
        }

        minHealthFactor[msg.sender] = _minHealthFactor;
    }

}
