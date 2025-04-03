// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    ERC4626Adapter,
    IERC4626Like
} from "src/pool-adapter/ERC4626Adapter.sol";

import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanSimpleProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";

import { T20 } from "pwn_protocol/test/helper/T20.sol";
import {
    UseCasesTest,
    MultiToken,
    IERC20
} from "pwn_protocol/test/fork/UseCases.fork.t.sol";


contract EulerERC4626AdapterForkTest is UseCasesTest {

    address constant EULER_VAULT = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 initialAmount = 1000e6;

    ERC4626Adapter adapter;

    constructor() {
        deploymentsSubpath = "/lib/pwn_protocol";
    }

    function setUp() override public {
        super.setUp();

        adapter = new ERC4626Adapter(address(deployment.hub));
        vm.prank(deployment.config.owner());
        deployment.config.registerPoolAdapter(EULER_VAULT, address(adapter));

        vm.prank(EULER_VAULT);
        IERC20(USDC).transfer(lender, initialAmount);

        // Supply to pool 1k USDC
        vm.startPrank(lender);
        IERC20(USDC).approve(EULER_VAULT, type(uint256).max);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
        IERC20(EULER_VAULT).approve(address(adapter), type(uint256).max);
        IERC4626Like(EULER_VAULT).deposit(initialAmount, lender);
        vm.stopPrank();

        vm.prank(borrower);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
    }

    function test_shouldWithdrawAndRepayToPool() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: EULER_VAULT
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

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
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 100e6);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        // Repay loan
        vm.prank(borrower);
        deployment.simpleLoan.repayLOAN(loanId);

        // LOAN token owner is original lender -> repay funds to the pool
        assertEq(IERC20(USDC).balanceOf(lender), 0);
        assertEq(IERC20(USDC).balanceOf(borrower), 0);
        vm.expectRevert("ERC721: invalid token ID");
        deployment.loanToken.ownerOf(loanId);
    }

    function test_shouldWithdrawFromPoolAndRepayToVault() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: EULER_VAULT
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = 100e6; // 100 USDC
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

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
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
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
        deployment.simpleLoan.repayLOAN(loanId);

        // LOAN token owner is not original lender -> repay funds to the Vault
        assertEq(IERC20(USDC).balanceOf(address(deployment.simpleLoan)), originalBalance + 100e6);
        assertEq(deployment.loanToken.ownerOf(loanId), newLender);
    }

    function testFuzz_shouldWithdrawAnyAmount(uint256 creditAmount) external {
        creditAmount = bound(creditAmount, 1, initialAmount);

        vm.warp(block.timestamp + 1 minutes);

        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: EULER_VAULT
        });

        // Update proposal
        proposal.creditAddress = USDC;
        proposal.creditAmount = creditAmount;
        proposal.proposerSpecHash = deployment.simpleLoan.getLenderSpecHash(lenderSpec);

        assertEq(IERC20(USDC).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
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
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
        assertEq(IERC20(USDC).balanceOf(borrower), creditAmount);
    }

}
