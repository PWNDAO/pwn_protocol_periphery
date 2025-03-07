// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import { PWNInstallmentsLoan } from "pwn/loan/terms/simple/loan/PWNInstallmentsLoan.sol";
import { PWNSimpleLoanElasticChainlinkProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";

import { PWNCrowdsourceLenderVault, IPWNLenderHook } from "src/crowdsource/PWNCrowdsourceLenderVault.sol";

import {
    DeploymentTest,
    PWNHubTags
} from "pwn_contracts/test/DeploymentTest.t.sol";


contract PWNCrowdsourceLenderVaultForkTest is DeploymentTest {

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant USD = address(840);

    PWNInstallmentsLoan loan;
    PWNInstallmentsLoan.LenderSpec lenderSpec;
    PWNSimpleLoanElasticChainlinkProposal.Proposal proposal;
    PWNSimpleLoanElasticChainlinkProposal.ProposalValues proposalValues;

    PWNCrowdsourceLenderVault lenderVault;
    address[4] lenders;
    uint256 initialAmount = 50_000e6;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        // > Prepare protocol
        loan = new PWNInstallmentsLoan(
            address(deployment.hub),
            address(deployment.loanToken),
            address(deployment.config),
            address(deployment.categoryRegistry)
        );

        vm.prank(deployment.protocolTimelock);
        deployment.chainlinkFeedRegistry.acceptOwnership();

        address[] memory addrs = new address[](3);
        addrs[0] = address(deployment.simpleLoanElasticChainlinkProposal);
        addrs[1] = address(deployment.simpleLoanElasticChainlinkProposal);
        addrs[2] = address(loan);

        bytes32[] memory tags = new bytes32[](3);
        tags[0] = PWNHubTags.LOAN_PROPOSAL;
        tags[1] = PWNHubTags.NONCE_MANAGER;
        tags[2] = PWNHubTags.ACTIVE_LOAN;

        vm.prank(deployment.protocolTimelock);
        deployment.hub.setTags(addrs, tags, true);

        vm.startPrank(deployment.protocolTimelock);
        deployment.chainlinkFeedRegistry.proposeFeed(ETH, USD, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        deployment.chainlinkFeedRegistry.confirmFeed(ETH, USD, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        deployment.chainlinkFeedRegistry.proposeFeed(address(USDC), USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        deployment.chainlinkFeedRegistry.confirmFeed(address(USDC), USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        vm.stopPrank();
        // < Prepare protocol

        address[] memory intermediaryDenominations = new address[](1);
        intermediaryDenominations[0] = USD;

        bool[] memory invertFlags = new bool[](2);
        invertFlags[0] = false;
        invertFlags[1] = true;

        proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(WETH),
            collateralId: 0,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: address(USDC),
            feedIntermediaryDenominations: intermediaryDenominations,
            feedInvertFlags: invertFlags,
            loanToValue: 8000,
            minCreditAmount: 150_000e6,
            availableCreditLimit: 0,
            utilizedCreditId: bytes32(0),
            fixedInterestAmount: 0,
            accruingInterestAPR: 100,
            durationOrDate: 730 days,
            expiration: uint40(block.timestamp + 60 days),
            allowedAcceptor: borrower,
            proposer: address(0), // to be set
            proposerSpecHash: bytes32(0), // to be set
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(loan)
        });
        proposalValues = PWNSimpleLoanElasticChainlinkProposal.ProposalValues({
            creditAmount: 180_000e6
        });

        lenderVault = new PWNCrowdsourceLenderVault(
            address(loan), "Bordel mortgage share", "BORDEL", PWNCrowdsourceLenderVault.Terms({
                collateralAddress: proposal.collateralAddress,
                creditAddress: proposal.creditAddress,
                feedIntermediaryDenominations: proposal.feedIntermediaryDenominations,
                feedInvertFlags: proposal.feedInvertFlags,
                loanToValue: proposal.loanToValue,
                minCreditAmount: proposal.minCreditAmount,
                fixedInterestAmount: proposal.fixedInterestAmount,
                accruingInterestAPR: proposal.accruingInterestAPR,
                durationOrDate: proposal.durationOrDate,
                expiration: proposal.expiration,
                allowedAcceptor: proposal.allowedAcceptor
            })
        );

        lenderSpec = PWNInstallmentsLoan.LenderSpec({
            lenderHook: IPWNLenderHook(address(lenderVault)),
            lenderHookParameters: ""
        });

        proposal.proposer = address(lenderVault);
        proposal.proposerSpecHash = loan.getLenderSpecHash(lenderSpec);

        vm.label(address(lenderVault.aave()), "Aave");

        lenders = [makeAddr("lender1"), makeAddr("lender2"), makeAddr("lender3"), makeAddr("lender4")];
        for (uint256 i; i < lenders.length; ++i) {
            vm.startPrank(aUSDC);
            USDC.transfer(lenders[i], initialAmount);

            vm.startPrank(lenders[i]);
            USDC.approve(address(lenderVault), type(uint256).max);
            lenderVault.deposit(initialAmount, lenders[i]);
            vm.stopPrank();
        }

        vm.prank(aWETH);
        WETH.transfer(borrower, 1000e18);
        vm.startPrank(borrower);
        WETH.approve(address(loan), type(uint256).max);
        USDC.approve(address(loan), type(uint256).max);
        vm.stopPrank();

        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
    }

}


contract PWNCrowdsourceLenderVault_Pooling_ForkTest is PWNCrowdsourceLenderVaultForkTest {

    function test_shouldWithdraw_whenPoolingStage() external {
        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        assertApproxEqAbs(USDC.balanceOf(lenders[0]), 0, 2);

        assertApproxEqAbs(lenderVault.maxWithdraw(lenders[0]), initialAmount, 2);

        vm.prank(lenders[0]);
        lenderVault.withdraw(initialAmount / 2, lenders[0], lenders[0]);

        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length - initialAmount / 2, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount / 2, 2);
        assertApproxEqAbs(USDC.balanceOf(lenders[0]), initialAmount / 2, 2);
    }

    function test_shouldRedeem_whenPoolingStage() external {
        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        assertApproxEqAbs(USDC.balanceOf(lenders[0]), 0, 2);

        assertApproxEqAbs(lenderVault.maxRedeem(lenders[0]), initialAmount, 2);

        uint256 shares = lenderVault.convertToShares(initialAmount / 2);
        vm.prank(lenders[0]);
        lenderVault.redeem(shares, lenders[0], lenders[0]);

        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length - initialAmount / 2, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount / 2, 2);
        assertApproxEqAbs(USDC.balanceOf(lenders[0]), initialAmount / 2, 2);
    }

    function test_shouldDeposit_whenPoolingStage() external {
        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        vm.prank(aUSDC);
        USDC.transfer(lenders[0], initialAmount);

        assertEq(lenderVault.maxDeposit(lenders[0]), type(uint256).max);

        vm.prank(lenders[0]);
        lenderVault.deposit(initialAmount, lenders[0]);

        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length + initialAmount, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), 2 * initialAmount, 2);
    }

    function test_shouldMint_whenPoolingStage() external {
        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        vm.prank(aUSDC);
        USDC.transfer(lenders[0], initialAmount);

        assertEq(lenderVault.maxMint(lenders[0]), type(uint256).max);

        uint256 shares = lenderVault.convertToShares(initialAmount);
        vm.prank(lenders[0]);
        lenderVault.mint(shares, lenders[0]);

        assertApproxEqAbs(lenderVault.totalAssets(), initialAmount * lenders.length + initialAmount, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), 2 * initialAmount, 2);
    }

    function test_loanStart() external {
        uint256 poolingTotalAssets = lenderVault.totalAssets();
        assertApproxEqAbs(IERC20(aUSDC).balanceOf(address(lenderVault)), 4 * initialAmount, 2);
        assertEq(USDC.balanceOf(borrower), 0);

        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, proposalValues);
        vm.prank(borrower);
        uint256 loanId = loan.createLOAN({
            proposalSpec: PWNInstallmentsLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                signature: ""
            }),
            lenderSpec: lenderSpec,
            extra: ""
        });

        assertEq(lenderVault.totalAssets(), poolingTotalAssets); // no change in total assets
        assertEq(IERC20(aUSDC).balanceOf(address(lenderVault)), 0); // no aave deposit after loan start
        assertEq(USDC.balanceOf(borrower), proposalValues.creditAmount); // borrower received the credit
        assertEq(lenderVault.totalCollateralAssets(), 0);
        assertEq(lenderVault.loanId(), loanId);
    }

}


contract PWNCrowdsourceLenderVault_Running_ForkTest is PWNCrowdsourceLenderVaultForkTest {

    uint256 loanId;
    uint256 unutilizedAmount;

    function setUp() override public virtual {
        super.setUp();

        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, proposalValues);
        vm.prank(borrower);
        loanId = loan.createLOAN({
            proposalSpec: PWNInstallmentsLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                signature: ""
            }),
            lenderSpec: lenderSpec,
            extra: ""
        });

        unutilizedAmount = initialAmount * lenders.length - proposalValues.creditAmount;
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(lenderVault)), unutilizedAmount, 2); // 20k
    }


    function test_shouldWithdraw_whenRunningStage() external {
        uint256 expectedTotalAssets = initialAmount * lenders.length;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        assertEq(IERC20(USDC).balanceOf(lenders[0]), 0);

        uint256 maxWithdraw = lenderVault.maxWithdraw(lenders[0]);
        assertApproxEqAbs(maxWithdraw, unutilizedAmount, 2);

        vm.prank(lenders[0]);
        lenderVault.withdraw(maxWithdraw, lenders[0], lenders[0]);

        assertApproxEqAbs(IERC20(USDC).balanceOf(lenders[0]), unutilizedAmount, 2);

        expectedTotalAssets -= maxWithdraw;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 180k
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount - unutilizedAmount, 2);
        assertApproxEqAbs(IERC20(USDC).balanceOf(lenders[0]), unutilizedAmount, 2);

        uint256 repayAmount = 30_000e6;
        vm.prank(borrower);
        loan.repayLOAN(loanId, repayAmount);

        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 180k

        vm.prank(lenders[1]);
        lenderVault.withdraw(20_000e6, lenders[1], lenders[1]);

        expectedTotalAssets -= 20_000e6;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 160k

        vm.prank(lenders[2]);
        lenderVault.withdraw(10_000e6, lenders[2], lenders[2]);

        expectedTotalAssets -= 10_000e6;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 150k
    }

    function test_shouldRedeem_whenRunningStage() external {
        uint256 expectedTotalAssets = initialAmount * lenders.length;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2);
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount, 2);
        assertEq(IERC20(USDC).balanceOf(lenders[0]), 0);

        uint256 maxRedeem = lenderVault.maxRedeem(lenders[0]);
        assertApproxEqAbs(maxRedeem, unutilizedAmount, 2);

        vm.prank(lenders[0]);
        lenderVault.redeem(maxRedeem, lenders[0], lenders[0]);

        assertApproxEqAbs(IERC20(USDC).balanceOf(lenders[0]), unutilizedAmount, 2);

        expectedTotalAssets -= maxRedeem;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 180k
        assertApproxEqAbs(lenderVault.balanceOf(lenders[0]), initialAmount - unutilizedAmount, 2);
        assertApproxEqAbs(IERC20(USDC).balanceOf(lenders[0]), unutilizedAmount, 2);

        uint256 repayAmount = 30_000e6;
        vm.prank(borrower);
        loan.repayLOAN(loanId, repayAmount);

        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 180k

        vm.prank(lenders[1]);
        lenderVault.redeem(20_000e6, lenders[1], lenders[1]);

        expectedTotalAssets -= 20_000e6;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 160k

        vm.prank(lenders[2]);
        lenderVault.redeem(10_000e6, lenders[2], lenders[2]);

        expectedTotalAssets -= 10_000e6;
        assertApproxEqAbs(lenderVault.totalAssets(), expectedTotalAssets, 2); // 150k
    }

    function test_shouldRevertDeposit_whenRunningStage() external {
        vm.expectRevert();
        vm.prank(lenders[0]);
        lenderVault.deposit(1, lenders[0]);
    }

    function test_shouldRevertMint_whenRunningStage() external {
        vm.expectRevert();
        vm.prank(lenders[0]);
        lenderVault.mint(1, lenders[0]);
    }

    function test_loanRepaid() external {
        uint256 runningTotalAssets = lenderVault.totalAssets();

        vm.prank(borrower);
        loan.repayLOAN(loanId, 0); // repay full amount

        assertEq(lenderVault.totalCollateralAssets(), 0);
        assertApproxEqAbs(lenderVault.totalAssets(), runningTotalAssets, 2);
    }

    function test_loanDefaulted() external {
        vm.warp(block.timestamp + proposal.durationOrDate);
        // Note: defaulted loan

        assertApproxEqAbs(lenderVault.totalAssets(), unutilizedAmount, 2);
        assertGt(lenderVault.totalCollateralAssets(), 0);
        assertGt(lenderVault.previewCollateralRedeem(50_000e6), 0);
    }

}


contract PWNCrowdsourceLenderVault_Ending_ForkTest is PWNCrowdsourceLenderVaultForkTest {

    modifier loanRepaid() {
        vm.prank(borrower);
        loan.repayLOAN(loanId, 0);
        _;
    }

    modifier loanDefaulted() {
        vm.warp(block.timestamp + proposal.durationOrDate);
        _;
    }

    uint256 loanId;
    uint256 unutilizedAmount;

    function setUp() override public virtual {
        super.setUp();

        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, proposalValues);
        vm.prank(borrower);
        loanId = loan.createLOAN({
            proposalSpec: PWNInstallmentsLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                signature: ""
            }),
            lenderSpec: lenderSpec,
            extra: ""
        });

        unutilizedAmount = initialAmount * lenders.length - proposalValues.creditAmount;
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(lenderVault)), unutilizedAmount, 2); // 20k
    }


    function test_shouldRevertWithdraw_whenEndingStage() external loanRepaid {
        vm.expectRevert();
        vm.prank(lenders[0]);
        lenderVault.withdraw(1, lenders[0], lenders[0]);
    }

    function test_shouldRedeem_whenEndingStage_whenLoanRepaid() external loanRepaid {
        uint256 donation = 1000 ether;
        vm.prank(aWETH);
        WETH.transfer(address(lenderVault), donation);

        // Note: any collateral asset donation should be redeemed

        for (uint256 i; i < lenders.length; ++i) {
            uint256 shares = lenderVault.balanceOf(lenders[i]);
            vm.prank(lenders[i]);
            lenderVault.redeem(shares, lenders[i], lenders[i]);

            assertApproxEqAbs(USDC.balanceOf(lenders[i]), initialAmount, 2);
            assertApproxEqAbs(WETH.balanceOf(lenders[i]), donation / 4, 2);
        }

        assertEq(lenderVault.totalAssets(), 0);
        assertEq(lenderVault.totalCollateralAssets(), 0);
    }

    function test_shouldRedeem_whenEndingStage_whenLoanDefaulted() external loanDefaulted {
        uint256 donation = 1000e6;
        vm.prank(aUSDC);
        USDC.transfer(address(lenderVault), donation);

        // Note: any undistributed asset (donation) should be redeemed

        (, PWNInstallmentsLoan.LOAN memory _loan) = loan.getLOAN(loanId);
        uint256 collAmount = _loan.collateral.amount;
        for (uint256 i; i < lenders.length; ++i) {
            uint256 shares = lenderVault.balanceOf(lenders[i]);
            vm.prank(lenders[i]);
            lenderVault.redeem(shares, lenders[i], lenders[i]);

            assertApproxEqAbs(USDC.balanceOf(lenders[i]), (unutilizedAmount + donation) / 4, 2);
            assertApproxEqAbs(WETH.balanceOf(lenders[i]), collAmount / 4, 2);
        }

        assertEq(lenderVault.totalAssets(), 0);
        assertEq(lenderVault.totalCollateralAssets(), 0);
    }

    function test_shouldRevertDeposit_whenEndingStage() external loanRepaid {
        vm.expectRevert();
        vm.prank(lenders[0]);
        lenderVault.deposit(1, lenders[0]);
    }

    function test_shouldRevertMint_whenEndingStage() external loanRepaid {
        vm.expectRevert();
        vm.prank(lenders[0]);
        lenderVault.mint(1, lenders[0]);
    }

}
