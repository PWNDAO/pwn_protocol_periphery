// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import { PWNInstallmentsLoan } from "pwn/loan/terms/simple/loan/PWNInstallmentsLoan.sol";
import { PWNSimpleLoanElasticChainlinkProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanElasticChainlinkProposal.sol";

import { PWNCrowdsourceLenderVault } from "src/crowdsource/PWNCrowdsourceLenderVault.sol";

import {
    DeploymentTest,
    PWNHubTags
} from "pwn_contracts/test/DeploymentTest.t.sol";


contract PWNCrowdsourceLenderVaultForkTest is DeploymentTest {

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant USD = address(840);

    PWNInstallmentsLoan loan;
    PWNSimpleLoanElasticChainlinkProposal.Proposal proposal;
    PWNSimpleLoanElasticChainlinkProposal.ProposalValues proposalValues;

    PWNCrowdsourceLenderVault lenderVault;
    address[4] lenders;
    uint256 initialAmount = 50_000e6;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public {
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
        deployment.chainlinkFeedRegistry.proposeFeed(USDC, USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        deployment.chainlinkFeedRegistry.confirmFeed(USDC, USD, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        vm.stopPrank();
        // < Prepare protocol

        address[] memory intermediaryDenominations = new address[](1);
        intermediaryDenominations[0] = USD;

        bool[] memory invertFlags = new bool[](2);
        invertFlags[0] = false;
        invertFlags[1] = true;

        proposal = PWNSimpleLoanElasticChainlinkProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: WETH,
            collateralId: 0,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: USDC,
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
            proposer: address(0),
            proposerSpecHash: bytes32(0),
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

        proposal.proposer = address(lenderVault);

        vm.label(address(lenderVault.aave()), "Aave");

        lenders = [makeAddr("lender1"), makeAddr("lender2"), makeAddr("lender3"), makeAddr("lender4")];
        for (uint256 i; i < lenders.length; ++i) {
            vm.startPrank(aUSDC);
            IERC20(USDC).transfer(lenders[i], initialAmount);

            vm.startPrank(lenders[i]);
            IERC20(USDC).approve(address(lenderVault), type(uint256).max);
            lenderVault.deposit(initialAmount, lenders[i]);
            vm.stopPrank();
        }

        vm.prank(aWETH);
        IERC20(WETH).transfer(borrower, 1000e18);
        vm.prank(borrower);
        IERC20(WETH).approve(address(loan), type(uint256).max);
    }


    function test_loanStart() external {
        bytes memory proposalData = deployment.simpleLoanElasticChainlinkProposal.encodeProposalData(proposal, proposalValues);

        vm.prank(borrower);
        loan.createLOAN({
            proposalSpec: PWNInstallmentsLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanElasticChainlinkProposal),
                proposalData: proposalData,
                signature: ""
            }),
            extra: ""
        });
    }

}
