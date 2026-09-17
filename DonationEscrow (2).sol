// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * DonationEscrow
 * Flow: Donation -> Locked Fund -> Milestone -> Evidence (off-chain, hash stored) ->
 *       Verification -> Release -> Impact (off-chain record)
 *
 * Simplified for a 24hr hackathon prototype: ONE campaign, a fixed set of
 * milestones created at deploy time, single verifier (the contract owner).
 */
contract DonationEscrow {
    address public owner;          // the "verifier" / NGO admin for the demo
    address payable public beneficiary; // where verified funds get released to

    uint256 public totalDonated;
    uint256 public totalReleased;

    struct Milestone {
        string description;      // e.g. "Purchase and distribute food kits"
        uint256 targetAmount;    // how much this milestone needs before release
        string evidenceHash;     // IPFS hash of uploaded evidence (set on submission)
        bool evidenceSubmitted;
        bool verified;
        bool released;
    }

    Milestone[] public milestones;

    // Track each donor's total contribution (this powers the "Donation Passport")
    mapping(address => uint256) public donorTotal;
    address[] public donors;
    mapping(address => bool) private isKnownDonor;

    event DonationReceived(address indexed donor, uint256 amount, uint256 newTotal);
    event EvidenceSubmitted(uint256 indexed milestoneIndex, string evidenceHash);
    event MilestoneVerified(uint256 indexed milestoneIndex);
    event FundsReleased(uint256 indexed milestoneIndex, uint256 amount, address beneficiary);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only verifier can call this");
        _;
    }

    constructor(address payable _beneficiary, string[] memory _descriptions, uint256[] memory _targets) {
        require(_descriptions.length == _targets.length, "Mismatched milestone arrays");
        owner = msg.sender;
        beneficiary = _beneficiary;

        for (uint256 i = 0; i < _descriptions.length; i++) {
            milestones.push(Milestone({
                description: _descriptions[i],
                targetAmount: _targets[i],
                evidenceHash: "",
                evidenceSubmitted: false,
                verified: false,
                released: false
            }));
        }
    }

    // --- DONATION -> LOCKED FUND ---
    function donate() external payable {
        require(msg.value > 0, "Send some POL to donate");

        totalDonated += msg.value;
        donorTotal[msg.sender] += msg.value;

        if (!isKnownDonor[msg.sender]) {
            isKnownDonor[msg.sender] = true;
            donors.push(msg.sender);
        }

        emit DonationReceived(msg.sender, msg.value, donorTotal[msg.sender]);
    }

    // --- EXPENSE -> EVIDENCE ---
    // NGO/admin submits proof (photo/receipt) already uploaded to IPFS; only the hash goes on-chain
    function submitEvidence(uint256 milestoneIndex, string calldata evidenceHash) external onlyOwner {
        require(milestoneIndex < milestones.length, "Invalid milestone");
        Milestone storage m = milestones[milestoneIndex];
        require(!m.released, "Already released");

        m.evidenceHash = evidenceHash;
        m.evidenceSubmitted = true;

        emit EvidenceSubmitted(milestoneIndex, evidenceHash);
    }

    // --- VERIFICATION ---
    // In the real system this would be a separate verifier role (+ AI pre-check off-chain).
    // For the demo, owner acts as the human verifier after reviewing the AI screening result.
    function verifyMilestone(uint256 milestoneIndex) external onlyOwner {
        require(milestoneIndex < milestones.length, "Invalid milestone");
        Milestone storage m = milestones[milestoneIndex];
        require(m.evidenceSubmitted, "No evidence submitted yet");
        require(!m.verified, "Already verified");

        m.verified = true;
        emit MilestoneVerified(milestoneIndex);
    }

    // --- RELEASE -> IMPACT ---
    function releaseFunds(uint256 milestoneIndex) external onlyOwner {
        require(milestoneIndex < milestones.length, "Invalid milestone");
        Milestone storage m = milestones[milestoneIndex];
        require(m.verified, "Milestone not verified yet");
        require(!m.released, "Already released");
        require(address(this).balance >= m.targetAmount, "Insufficient locked funds");

        m.released = true;
        totalReleased += m.targetAmount;

        (bool sent, ) = beneficiary.call{value: m.targetAmount}("");
        require(sent, "Transfer failed");

        emit FundsReleased(milestoneIndex, m.targetAmount, beneficiary);
    }

    // --- VIEW HELPERS FOR YOUR FRONTEND ---
    function getMilestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    function getMilestone(uint256 i) external view returns (
        string memory description,
        uint256 targetAmount,
        string memory evidenceHash,
        bool evidenceSubmitted,
        bool verified,
        bool released
    ) {
        Milestone storage m = milestones[i];
        return (m.description, m.targetAmount, m.evidenceHash, m.evidenceSubmitted, m.verified, m.released);
    }

    function getDonorCount() external view returns (uint256) {
        return donors.length;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
