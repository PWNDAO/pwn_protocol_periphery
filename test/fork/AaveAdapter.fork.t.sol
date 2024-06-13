// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    AaveAdapter,
    IAavePoolLike
} from "src/pool-adapter/AaveAdapter.sol";

import {
    PWNSimpleLoanSimpleProposal,
    PWNSimpleLoan
} from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";

import { T20 } from "pwn_contracts/test/helper/T20.sol";
import {
    UseCasesTest,
    MultiToken,
    IERC20
} from "pwn_contracts/test/fork/UseCases.fork.t.sol";


contract AaveAdapterTest is UseCasesTest {

    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    AaveAdapter adapter;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public {
        super.setUp();

        adapter = new AaveAdapter(address(deployment.hub));
        deployment.config.registerPoolAdapter(AAVE_POOL, address(adapter));

        vm.prank(0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503);
        IERC20(USDC).transfer(lender, 1000e6);

        // Supply to pool 1k USDC
        vm.startPrank(lender);
        IERC20(USDC).approve(AAVE_POOL, type(uint256).max);
        IAavePoolLike(AAVE_POOL).supply(USDC, 1000e6, lender, 0);
        IERC20(aUSDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
        vm.stopPrank();

        vm.prank(borrower);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
    }

    function test_shouldWithdrawAndRepayToPool() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE_POOL
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

        assertApproxEqAbs(IERC20(aUSDC).balanceOf(lender), 1000e6, 1);
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });

        // Check balance
        assertApproxEqAbs(IERC20(aUSDC).balanceOf(lender), 900e6, 1);
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 100e6);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // LOAN token owner is original lender -> repay funds to the pool
        assertGe(IERC20(aUSDC).balanceOf(lender), 1000e6); // greater than or equal becase pool may have accrued interest
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);
        vm.expectRevert("ERC721: invalid token ID");
        deployment.loanToken.ownerOf(loanId);
    }

    function test_shouldWithdrawFromPoolAndRepayToVault() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE_POOL
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

        assertApproxEqAbs(IERC20(aUSDC).balanceOf(lender), 1000e6, 1);
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0,
                permitData: ""
            }),
            extra: ""
        });

        // Check balance
        assertApproxEqAbs(IERC20(aUSDC).balanceOf(lender), 900e6, 1);
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 100e6);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        address newLender = makeAddr("new lender");

        vm.prank(lender);
        deployment.loanToken.transferFrom(lender, newLender, loanId);

        uint256 originalBalance = IERC20(USDC).balanceOf(address(deployment.simpleLoan));

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN({
            loanId: loanId,
            permitData: ""
        });

        // LOAN token owner is not original lender -> repay funds to the Vault
        assertGe(IERC20(aUSDC).balanceOf(lender), 900e6);
        assertEq(IERC20(USDC).balanceOf(address(deployment.simpleLoan)), originalBalance + 100e6);
        assertEq(deployment.loanToken.ownerOf(loanId), newLender);
    }

}
