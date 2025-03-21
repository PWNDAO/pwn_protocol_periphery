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
} from "pwn_protocol/test/DeploymentTest.t.sol";


contract WorldIdAcceptorControllerForkTest is DeploymentTest {

    address constant WLD = 0x2cFc85d8E48F8EAB294be644d9E25C3030863003;
    address constant uniWLD = 0x610E319b3A3Ab56A0eD5562927D37c233774ba39;

    IWorldID constant worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
    string constant appId = "app_9b6d733aa881b7be963557bef509cd17"; // "app_17abe44eaf47c99566f5378aa4e19463";
    string constant actionId = "supply"; // "verify-humanness";

    WorldIdAcceptorController controller;
    WorldIdAcceptorController.AcceptorData acceptorData;

    constructor() {
        deploymentsSubpath = "/lib/pwn_protocol";
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

        borrower = 0x0a1b2c3d4E5f67890123456789Abcdef01234567;
        controller = new WorldIdAcceptorController(worldId, appId, actionId);
        acceptorData = WorldIdAcceptorController.AcceptorData({ // test verification data
            root: 0x28cce7a33cd773f2fd5eedb1c0492fd837d91514b284bfdee8ea1a31e1fbb24b,
            nullifierHash: 0x02cc618bed55921ea5ed3840edecda4b7ac8fb4e4d64deb5f009673cb1bde146,
            proof: [uint256(0x1fca9c3abde1719295742e8aec441113fbff58812b8e463cb40e5c7bc7a43f4c), 0x24974b237be75b67dd6297d78157ef42357e02e01cbb1738a82029d0d63df673, 0x2cb84acb3f8185b758092c1cf7e5bdc9400aeeb511eb11b6a74d9495448a7878, 0x19eb7725b13da035f281df19c4ed7f1376407ceed07a2d502be06fe94c0b5755, 0x2abe6b048bfff0a6787ec48e39a69d600b24e1b6f68b1f1ad8f45adddb46dbf8, 0x2703207f99039bdb7347eba0af4b8b26d7bcb7f2bee32960d7f1c33c79612587, 0x185bf8eb073bf44c70969b9336d88edf677ac47643358fca6d0f6e57777d5226, 0x054e72291058a37728bd0b3407d56cfa82d4200af885f8740e8451c548d46f64]
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
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });
    }

}
