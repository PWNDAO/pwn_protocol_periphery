// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { ERC4626, ERC20, IERC20, IERC20Metadata, Math, SafeERC20 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";

import { PWNInstallmentsLoan, LOANStatus, IPWNLenderHook } from "pwn/loan/terms/simple/loan/PWNInstallmentsLoan.sol";
import {
    PWNSimpleLoanElasticChainlinkProposal
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";
import { PWNLOAN } from "pwn/loan/token/PWNLOAN.sol";

import { IAavePoolLike } from "src/interfaces/IAavePoolLike.sol";


/**
 * @title PWNCrowdsourceLenderVault
 * @notice A vault that pools assets to lend through a PWNInstallmentsLoan contract.
 */
contract PWNCrowdsourceLenderVault is ERC4626, IPWNLenderHook {
    using Math for uint256;

    /**
     * @notice The Aave lending pool contract.
     * @dev Aave is used to earn interest on the assets while they are being pooled.
     */
    IAavePoolLike constant public aave = IAavePoolLike(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    /**
     * @notice The proposal contract that creates the loan proposal.
     */
    PWNSimpleLoanElasticChainlinkProposal constant public proposalContract = PWNSimpleLoanElasticChainlinkProposal(0xBA58E16BE93dAdcBB74a194bDfD9E5933b24016B);
    /**
     * @notice The PWNLOAN token contract.
     * @dev Is used to check the owner of the loan in the onLoanCreated hook.
     */
    PWNLOAN constant public loanToken = PWNLOAN(0x4440C069272cC34b80C7B11bEE657D0349Ba9C23);

    /**
     * @notice The PWNInstallmentsLoan contract through which the loan is created.
     */
    PWNInstallmentsLoan immutable public loanContract; // = PWNInstallmentsLoan(address(10000000)); // TBD

    /**
     * @notice The address of the aToken for the asset, if exists.
     * @dev The aToken is used to earn interest on the assets while they are being pooled.
     */
    address immutable internal aAsset;
    /**
     * @notice The address of the collateral token.
     */
    address immutable internal collateralAddr;
    /**
     * @notice The number of decimals of the collateral token.
     */
    uint8 immutable internal collateralDecimals;
    /**
     * @notice The hash of the loan proposal.
     * @dev The proposal is made on vault deployment.
     */
    bytes32 immutable internal proposalHash;

    /**
     * @notice The ID of the loan funded by the vault.
     */
    uint256 public loanId;

    /**
     * @notice Whether the loan has ended.
     * @dev The loan ends when it is repaid or defaulted.
     */
    bool internal loanEnded;

    /**
     * @notice The stages of the vault.
     * @dev The vault can be in the POOLING, RUNNING, or ENDING stage.
     * POOLING: The vault is pooling assets. Anyone can freely deposit and withdraw. The vault automatically supplies assets to Aave, if possible.
     * RUNNING: The vault has funded a loan and is running. No new deposits are allowed. The vault automatically claims repayments on every withdrawal.
     * ENDING: The funded loan ended. Only redeeming is allowed. The vault automatically claims the remaining loan amount or defaulted collateral.
     */
    enum Stage {
        POOLING, RUNNING, ENDING
    }

    /**
     * @notice The terms of the loan proposal.
     */
    struct Terms {
        address collateralAddress;
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address allowedAcceptor;
    }

    /**
     * @notice Emitted when collateral is withdrawn.
     */
    event WithdrawCollateral(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );


    constructor(
        address _loan,
        string memory _name,
        string memory _symbol,
        Terms memory _terms
    ) ERC4626(IERC20(_terms.creditAddress)) ERC20(_name, _symbol) {
        loanContract = PWNInstallmentsLoan(_loan);

        collateralAddr = _terms.collateralAddress;
        (bool success, uint8 decimals) = _tryGetAssetDecimals_child(IERC20(collateralAddr));
        if (!success) {
            revert("PWNCrowdsourceLenderVault: collateral token missing decimals");
        }
        collateralDecimals = decimals;

        proposalHash = proposalContract.makeProposal(
            PWNSimpleLoanElasticChainlinkProposal.Proposal({
                collateralCategory: MultiToken.Category.ERC20,
                collateralAddress: _terms.collateralAddress,
                collateralId: 0,
                checkCollateralStateFingerprint: false,
                collateralStateFingerprint: bytes32(0),
                creditAddress: _terms.creditAddress,
                feedIntermediaryDenominations: _terms.feedIntermediaryDenominations,
                feedInvertFlags: _terms.feedInvertFlags,
                loanToValue: _terms.loanToValue,
                minCreditAmount: _terms.minCreditAmount,
                availableCreditLimit: 0,
                utilizedCreditId: bytes32(0),
                fixedInterestAmount: _terms.fixedInterestAmount,
                accruingInterestAPR: _terms.accruingInterestAPR,
                durationOrDate: _terms.durationOrDate,
                expiration: _terms.expiration,
                allowedAcceptor: _terms.allowedAcceptor,
                proposer: address(this),
                proposerSpecHash: loanContract.getLenderSpecHash(PWNInstallmentsLoan.LenderSpec({
                    lenderHook: IPWNLenderHook(address(this)),
                    lenderHookParameters: ""
                })),
                isOffer: true,
                refinancingLoanId: 0,
                nonceSpace: 0,
                nonce: 0,
                loanContract: address(loanContract)
            })
        );

        IERC20(asset()).approve(address(loanContract), type(uint256).max);

        IAavePoolLike.ReserveData memory reserveData = aave.getReserveData(asset());
        aAsset = reserveData.aTokenAddress;
        if (aAsset != address(0)) {
            IERC20(asset()).approve(address(aave), type(uint256).max);
        }
    }


    /**
     * @notice The stage of the vault.
     */
    function stage() internal view returns (Stage) {
        if (loanId == 0) {
            return Stage.POOLING;
        } else if (loanEnded) {
            return Stage.ENDING;
        }
        return Stage.RUNNING;
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626                                               *|
    |*----------------------------------------------------------*/

    /** @inheritdoc ERC4626*/
    function totalAssets() public view override returns (uint256) {
        uint256 additionalAssets;
        Stage _stage = stage();
        if (_stage == Stage.POOLING) {
            if (aAsset != address(0)) {
                // Note: assuming aToken:token ratio is always 1:1
                additionalAssets = IERC20(aAsset).balanceOf(address(this));
            }
        } else if (_stage == Stage.RUNNING) {
            (uint8 status, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
            additionalAssets = loan.unclaimedAmount;
            if (status == LOANStatus.RUNNING) {
                additionalAssets += loanContract.loanRepaymentAmount(loanId);
            }
        }
        return IERC20(asset()).balanceOf(address(this)) + additionalAssets;
    }

    // # Max

    /** @inheritdoc ERC4626*/
    function maxDeposit(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    /** @inheritdoc ERC4626*/
    function maxMint(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    /** @inheritdoc ERC4626*/
    function maxWithdraw(address owner) public view override returns (uint256 max) {
        Stage _stage = stage();
        if (_stage == Stage.ENDING) {
            return 0; // no withdraws allowed, use redeem
        }

        max = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        if (_stage == Stage.RUNNING) {
            max = Math.min(max, _availableLiquidity());
        }
    }

    /** @inheritdoc ERC4626*/
    function maxRedeem(address owner) public view override returns (uint256 max) {
        max = balanceOf(owner);
        if (stage() == Stage.RUNNING) {
            max = Math.min(max, _convertToShares(_availableLiquidity(), Math.Rounding.Up));
        }
    }

    // # Preview

    /** @inheritdoc ERC4626*/
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: deposit disabled");
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @inheritdoc ERC4626*/
    function previewMint(uint256 shares) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: mint disabled");
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    /** @inheritdoc ERC4626*/
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        require(stage() != Stage.ENDING, "PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /** @inheritdoc ERC4626*/
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    // # Actions

    /** @inheritdoc ERC4626*/
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = previewDeposit(assets);
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = previewMint(shares);
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        _claimLoanIfPossible();
        shares = previewWithdraw(assets);
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        _claimLoanIfPossible();

        uint256 collAssets;
        if (stage() == Stage.ENDING) {
            // Note: need to calculate collateral assets before calling _withdraw which burns shares and changes totalSupply
            collAssets = _convertToCollateralAssets(shares, Math.Rounding.Down);
        }

        assets = previewRedeem(shares);
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        if (collAssets > 0) {
            SafeERC20.safeTransfer(IERC20(collateralAddr), receiver, collAssets);
            emit WithdrawCollateral(msg.sender, receiver, owner, collAssets, shares);
        }
    }

    /** @dev Must not be called when in other than RUNNING stage */
    function _availableLiquidity() internal view returns (uint256) {
        (, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
        return IERC20(asset()).balanceOf(address(this)) + loan.unclaimedAmount;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        if (aAsset != address(0)) {
            aave.supply(asset(), assets, address(this), 0);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        if (aAsset != address(0) && stage() == Stage.POOLING) {
            aave.withdraw(asset(), assets, address(this));
        }
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _claimLoanIfPossible() internal {
        if (stage() == Stage.RUNNING) {
            (uint8 status, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
            if (status == LOANStatus.REPAID || status == LOANStatus.DEFAULTED) {
                loanEnded = true;
            }
            if (loan.unclaimedAmount > 0 || status == LOANStatus.DEFAULTED) {
                loanContract.claimLOAN(loanId);
            }
        }
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626-LIKE COLLATERAL FUNCTIONS                     *|
    |*----------------------------------------------------------*/

    /** @notice ERC4626-like function that returns the total amount of the underlying collateral asset that is “managed” by Vault. */
    function totalCollateralAssets() public view returns (uint256) {
        uint256 additionalCollateralAssets;
        if (stage() == Stage.RUNNING) {
            (uint8 status, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
            if (status == LOANStatus.DEFAULTED) {
                additionalCollateralAssets += loan.collateral.amount;
            }
        }
        return IERC20(collateralAddr).balanceOf(address(this)) + additionalCollateralAssets;
    }

    /**
     * @notice ERC4626-like function that allows an on-chain or off-chain user to simulate the effects
     * of their collateral redeemption at the current block, given current on-chain conditions.
     */
    function previewCollateralRedeem(uint256 shares) public view returns (uint256) {
        Stage _stage = stage();
        if (_stage == Stage.RUNNING) {
            (uint8 status, ) = loanContract.getLOAN(loanId);
            require(status == LOANStatus.DEFAULTED, "PWNCrowdsourceLenderVault: collateral redeem disabled");
        } else {
            require(_stage == Stage.ENDING, "PWNCrowdsourceLenderVault: collateral redeem disabled");
        }

        return _convertToCollateralAssets(shares, Math.Rounding.Down);
    }

    function _convertToCollateralAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        uint256 _totalCollateralAssets = totalCollateralAssets();
        if (_totalCollateralAssets == 0) return 0;

        // Note: increase share decimals if smaller than collateral decimals
        uint256 decimalAdjustment = 10 ** (collateralDecimals - Math.min(collateralDecimals, decimals()));
        return (shares * decimalAdjustment).mulDiv(_totalCollateralAssets, totalSupply() * decimalAdjustment, rounding);
    }


    /*----------------------------------------------------------*|
    |*  # PWN LENDER HOOK                                       *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IPWNLenderHook*/
    function onLoanCreated(
        uint256 loanId_,
        bytes32 proposalHash_,
        address lender,
        address creditAddress,
        uint256 /* creditAmount */,
        bytes calldata lenderParameters
    ) external {
        require(msg.sender == address(loanContract));
        require(loanToken.ownerOf(loanId_) == address(this));
        require(loanId == 0);

        require(proposalHash_ == proposalHash);
        require(lender == address(this));
        require(creditAddress == asset());
        require(lenderParameters.length == 0);

        loanId = loanId_;
        if (aAsset != address(0)) {
            aave.withdraw(asset(), type(uint256).max, address(this));
        }
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    function _tryGetAssetDecimals_child(IERC20 asset_) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = address(asset_).staticcall(
            abi.encodeWithSelector(IERC20Metadata.decimals.selector)
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

}
