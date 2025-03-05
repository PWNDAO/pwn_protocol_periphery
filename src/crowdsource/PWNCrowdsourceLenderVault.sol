// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { ERC4626, IERC20, ERC20, Math, SafeERC20 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import { IERC721Receiver } from "openzeppelin/interfaces/IERC721Receiver.sol";

import { PWNInstallmentsLoan, LOANStatus } from "pwn/loan/terms/simple/loan/PWNInstallmentsLoan.sol";
import {
    PWNSimpleLoanElasticChainlinkProposal
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";
import { PWNLOAN } from "pwn/loan/token/PWNLOAN.sol";

import { IAavePoolLike } from "src/interfaces/IAavePoolLike.sol";


contract PWNCrowdsourceLenderVault is ERC4626, IERC721Receiver {
    using Math for uint256;

    IAavePoolLike constant public aave = IAavePoolLike(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    PWNSimpleLoanElasticChainlinkProposal constant public proposalContract = PWNSimpleLoanElasticChainlinkProposal(0xBA58E16BE93dAdcBB74a194bDfD9E5933b24016B);
    PWNLOAN constant public loanToken = PWNLOAN(0x4440C069272cC34b80C7B11bEE657D0349Ba9C23);

    PWNInstallmentsLoan immutable public loanContract; // = PWNInstallmentsLoan(address(10000000)); // TBD

    address immutable internal creditAddr;
    address immutable internal aCreditAddr;
    address immutable internal collateralAddr;

    uint256 public loanId;
    bool internal loanEnded;

    enum Stage {
        POOLING, RUNNING, ENDING
    }

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
        creditAddr = _terms.creditAddress;
        collateralAddr = _terms.collateralAddress;
        proposalContract.makeProposal(
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
                proposerSpecHash: bytes32(0),
                isOffer: true,
                refinancingLoanId: 0,
                nonceSpace: 0,
                nonce: 0,
                loanContract: address(loanContract)
            })
        );
        IERC20(creditAddr).approve(address(loanContract), type(uint256).max);
        IAavePoolLike.ReserveData memory reserveData = aave.getReserveData(creditAddr);
        aCreditAddr = reserveData.aTokenAddress;
        if (aCreditAddr != address(0)) {
            IERC20(creditAddr).approve(address(aave), type(uint256).max);
        }
    }


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

    function totalAssets() public view override returns (uint256) {
        uint256 additionalAssets;
        Stage _stage = stage();
        if (_stage == Stage.POOLING) {
            if (aCreditAddr != address(0)) {
                // Note: assuming aToken:token ratio is always 1:1
                additionalAssets = IERC20(aCreditAddr).balanceOf(address(this));
            }
        } else if (_stage == Stage.RUNNING) {
            (uint8 status, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
            additionalAssets = loan.unclaimedAmount;
            if (status == LOANStatus.RUNNING) {
                additionalAssets += loanContract.loanRepaymentAmount(loanId);
            }
        }
        return IERC20(creditAddr).balanceOf(address(this)) + additionalAssets;
    }

    // # Max

    function maxDeposit(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    function maxMint(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    function maxWithdraw(address owner) public view override returns (uint256 max) {
        max = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        if (stage() == Stage.RUNNING) {
            max = Math.min(max, _availableLiquidity());
        }
    }

    function maxRedeem(address owner) public view override returns (uint256 max) {
        max = balanceOf(owner);
        if (stage() == Stage.RUNNING) {
            max = Math.min(max, _convertToShares(_availableLiquidity(), Math.Rounding.Up));
        }
    }

    // # Preview

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: deposit disabled");
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: mint disabled");
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        require(stage() != Stage.ENDING, "PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        return _convertToShares(assets, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    // # Actions

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        _claimLoanIfPossible();
        shares = super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        _claimLoanIfPossible();
        assets = super.redeem(shares, receiver, owner);
        _redeemCollateralIfPossible(shares, receiver, owner);
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626 - INTERNALS                                   *|
    |*----------------------------------------------------------*/

    /** @dev Must not be called when in other than RUNNING stage */
    function _availableLiquidity() internal view returns (uint256) {
        (, PWNInstallmentsLoan.LOAN memory loan) = loanContract.getLOAN(loanId);
        return IERC20(creditAddr).balanceOf(address(this)) + loan.unclaimedAmount;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        if (aCreditAddr != address(0)) {
            aave.supply(creditAddr, assets, address(this), 0);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        if (aCreditAddr != address(0) && stage() == Stage.POOLING) {
            aave.withdraw(creditAddr, assets, address(this));
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

    function _redeemCollateralIfPossible(uint256 shares, address receiver, address owner) internal {
        if (stage() == Stage.ENDING) {
            uint256 collAssets = previewCollateralRedeem(shares);
            if (collAssets > 0) {
                SafeERC20.safeTransfer(IERC20(collateralAddr), receiver, collAssets);
                emit WithdrawCollateral(msg.sender, receiver, owner, collAssets, shares);
            }
        }
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626-LIKE COLLATERAL FUNCTIONS                     *|
    |*----------------------------------------------------------*/

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

    function previewCollateralRedeem(uint256 shares) public view returns (uint256) {
        require(stage() == Stage.ENDING, "PWNCrowdsourceLenderVault: collateral redeem disabled");
        return _convertToCollateralAssets(shares, Math.Rounding.Down);
    }

    function _convertToCollateralAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalCollateralAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }


    /*----------------------------------------------------------*|
    |*  # ERC721 RECEIVER                                       *|
    |*----------------------------------------------------------*/

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(loanContract));
        require(operator == address(loanContract));
        require(from == address(0));
        require(loanToken.ownerOf(tokenId) == address(this));
        require(loanId == 0);

        loanId = tokenId;
        if (aCreditAddr != address(0)) {
            aave.withdraw(creditAddr, type(uint256).max, address(this));
        }

        return IERC721Receiver.onERC721Received.selector;
    }

}
