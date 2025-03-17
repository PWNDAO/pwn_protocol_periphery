// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import {
    WorldIdAcceptorController,
    IWorldID
} from "src/acceptor-controller/WorldIdAcceptorController.sol";

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanSimpleProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";

import {
    DeploymentTest,
    PWNSimpleLoan,
    PWNSimpleLoanSimpleProposal
} from "pwn_contracts/test/DeploymentTest.t.sol";


contract WorldIdAcceptorControllerForkTest is DeploymentTest {

    address constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address constant uniWLD = 0x610E319b3A3Ab56A0eD5562927D37c233774ba39;

    IWorldID constant worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
    string constant appId = "app_17abe44eaf47c99566f5378aa4e19463";
    string constant actionId = "verify-humanness";

    WorldIdAcceptorController controller;
    WorldIdAcceptorController.AcceptorData acceptorData;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public {
        vm.createSelectFork("world");

        super.setUp();

        // > Prepare protocol
        deployment.simpleLoanSimpleProposal = new PWNSimpleLoanSimpleProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );

        address[] memory addresses = new address[](2);
        addresses[0] = address(deployment.simpleLoanSimpleProposal);
        addresses[1] = address(deployment.simpleLoanSimpleProposal);
        bytes32[] memory tags = new bytes32[](2);
        tags[0] = PWNHubTags.LOAN_PROPOSAL;
        tags[1] = PWNHubTags.NONCE_MANAGER;
        vm.prank(deployment.protocolTimelock);
        deployment.hub.setTags(addresses, tags, true);
        // < Prepare protocol

        controller = new WorldIdAcceptorController(worldId, appId, actionId);
        acceptorData = WorldIdAcceptorController.AcceptorData({ // test verification data
            root: 0,
            nullifierHash: 1,
            proof: [uint256(2), 3, 4, 5, 6, 7, 8, 9]
        });

        vm.startPrank(uniWLD);
        IERC20(WLD).transfer(lender, 100 ether);
        IERC20(WLD).transfer(borrower, 100 ether);
        vm.stopPrank();

        vm.prank(lender);
        IERC20(WLD).approve(address(deployment.simpleLoan), type(uint256).max);
        vm.prank(borrower);
        IERC20(WLD).approve(address(deployment.simpleLoan), type(uint256).max);

        vm.label(address(worldId), "WorldId");
    }

    function test_shouldPass_whenValidWorldId() external {
        vm.skip(true);

        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec(lender);

        PWNSimpleLoanSimpleProposal.Proposal memory proposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: WLD,
            collateralId: 0,
            collateralAmount: 10 ether,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: WLD,
            creditAmount: 10 ether,
            availableCreditLimit: 0,
            utilizedCreditId: bytes32(0),
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 5 days,
            expiration: uint40(block.timestamp + 5 days),
            acceptorController: address(controller),
            acceptorControllerData: "",
            proposer: lender,
            proposerSpecHash: keccak256(abi.encode(lenderSpec)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(deployment.simpleLoan)
        });

        PWNSimpleLoanSimpleProposal.ProposalValues memory proposalValues = PWNSimpleLoanSimpleProposal.ProposalValues(
            abi.encode(acceptorData)
        );

        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal, proposalValues);

        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({ // TBD
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });
    }

}
