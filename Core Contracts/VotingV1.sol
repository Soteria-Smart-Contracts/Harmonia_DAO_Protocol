//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.17;


contract VotingSystemV1 {
    // Proposal executioner's bonus, proposal incentive burn percentage 
    address public DAO;
    address public CLD;
    uint256 public MemberHolding;
    // These two are in Basis Points
    uint256 public ExecusCut;
    uint256 public BurnCut;

    event ProposalCreated(address proposer, uint256 proposalID, uint256 voteStart, uint256 voteEnd);
    event ProposalPassed(address executor, uint256 proposalId, uint256 amountBurned, uint256 executShare);
    event ProposalNotPassed(address executor, uint256 proposalId, uint256 amountBurned, uint256 executShare);
    event CastedVote(uint256 proposalId, string option, uint256 votesCasted);
    event ProposalIncentivized(address donator, uint256 proposalId, uint256 amountDonated);
    event IncentiveWithdrawed(uint256 remainingIncentive);
    event NewDAOAddress(address NewAddress);

    enum Vote{
        YEA,
        NAY
    }

    enum VoteResult{
        VotingIncomplete,
        Approved,
        Refused
    }

    //Create vote status enum instead of using uint8

    struct ProposalCore {
        uint256 ProposalID;      //DAO Proposal for voting instance
        uint256 VoteStarts;      //Unix Time
        uint256 VoteEnds;        //Unix Time
        VoteResult Result;       //Using VoteResult enum
        uint256 ActiveVoters;    //Total Number of users that have voted
        uint256 YEAvotes;        //Votes to approve
        uint256 NAYvotes;        //Votes to refuse
        bool Executed;           //Updated if the proposal utilising this instance has been executed by the DAO
        uint256 TotalIncentive;  //Total amount of CLD donated to this proposal for voting incentives, burning and execution reward
        uint256 IncentivePerVote;//Total amount of CLD per CLD voted 
        uint256 CLDToBurn;       //Total amount of CLD to be burned on proposal execution
        uint256 CLDToExecutioner;//Total amount of CLD to be sent to the address that pays the gas for executing the proposal
    }

    struct VoterDetails {
        uint256 VotesLocked;
        uint256 AmountDonated;
        bool Voted;
        bool IsExecutioner;
    }

    // Proposals being tracked by id here
    ProposalCore[] public VotingInstances;
    // Map user addresses over their info
    mapping (uint256 => mapping (address => VoterDetails)) internal VoterInfo;
 
    modifier OnlyDAO{ 
        require(msg.sender == address(DAO), 'This can only be done by the DAO');
        _;
    }

    constructor(address CLDAddr, address DAOAddr, uint8 _ExecusCut, uint8 _BurnCut) 
    {
        ExecusCut = _ExecusCut;
        BurnCut = _BurnCut;
        DAO = DAOAddr;
        CLD = CLDAddr;

        // TO DO insert poetic proposal #0 here
    }

    function IncentivizeProposal(uint256 proposalId, uint256 amount) external {
        require(ERC20(CLD).transferFrom(msg.sender, address(this), amount), "VotingSystemV1.IncentivizeProposal: You do not have enough CLD to incentivize this proposal or you may not have given this contract enough allowance");
        require(VotingInstances[proposalId].Result == VoteResult(0), 'VotingSystemV1.IncentivizeProposal: This proposal has ended');
        require(block.timestamp <= VotingInstances[proposalId].VoteEnds, "VotingSystemV1.IncentivizeProposal: The voting period has ended, save for the next proposal!");

        VotingInstances[proposalId].TotalIncentive += amount;
        VoterInfo[proposalId][msg.sender].AmountDonated += amount;

        _updateTaxesAndIndIncentive(proposalId, true);
        emit ProposalIncentivized(msg.sender, proposalId, VotingInstances[proposalId].TotalIncentive);
    }//Checked

    function CastVote(uint256 amount, uint256 proposalId, Vote VoteChoice) external {
        require(
            ERC20(CLD).allowance(msg.sender, address(this)) >= amount, 
            "VotingSystemV1.CastVote: You have not given the voting contract enough allowance"
        );
        require(
            ERC20(CLD).transferFrom(msg.sender, address(this), amount), 
            "VotingSystemV1.CastVote: You do not have enough CLD to vote this amount"
        );
        require(
            VoteChoice == Vote(0) || VoteChoice == Vote(1), 
            "VotingSystemV1.CastVote: You must either vote 'Yea' or 'Nay'"
        );
        require(!VoterInfo[proposalId][msg.sender].Voted, "VotingSystemV1.CastVote: You already voted in this proposal");
        require(block.timestamp >= VotingInstances[proposalId].VoteStarts && block.timestamp <= VotingInstances[proposalId].VoteEnds, "VotingSystemV1.CastVote: This instance is not currently in voting");


        if(VoteChoice == Vote(0)) {
            VotingInstances[proposalId].YEAvotes += amount;
            emit CastedVote(proposalId, "Yes", amount);
        } else {
            VotingInstances[proposalId].NAYvotes += amount;
            emit CastedVote(proposalId, "No", amount);
        }
        VoterInfo[proposalId][msg.sender].VotesLocked += amount;
        VoterInfo[proposalId][msg.sender].Voted = true;
        VotingInstances[proposalId].ActiveVoters += 1;

        _updateTaxesAndIndIncentive(proposalId, false);
    }

    // Proposal execution code
    function ExecuteProposal(uint256 proposalId) external {
        require(block.timestamp >= VotingInstances[proposalId].VoteEnds, 
            "VotingSystemV1.ExecuteProposal: Voting has not ended");      
        require(VotingInstances[proposalId].Executed == false, 
            "VotingSystemV1.ExecuteProposal: Proposal already executed!");
        require(VotingInstances[proposalId].ActiveVoters > 0, 
            "VotingSystemV1.ExecuteProposal: Can't execute proposals without voters!");
        VoterInfo[proposalId][msg.sender].IsExecutioner = true;

        ERC20(CLD).Burn(VotingInstances[proposalId].CLDToBurn);
//        VotingInstances[proposalId].IncentiveAmount -= VotingInstances[proposalId].CLDToBurn;  //Should leave this for archival
        
        ERC20(CLD).transfer(msg.sender, VotingInstances[proposalId].CLDToExecutioner);
//        VotingInstances[proposalId].IncentiveAmount -= VotingInstances[proposalId].AmountToExecutioner; //Should leave this for archival

        if (VotingInstances[proposalId].YEAvotes > VotingInstances[proposalId].NAYvotes) {
            // TO DO Connect this to the real core
            VotingInstances[proposalId].Passed = 1;
//            FakeDAO(DAO).ExecuteCoreProposal(proposalId, true); //turn into interface

            emit ProposalPassed(msg.sender, proposalId, VotingInstances[proposalId].AmountToBurn, VotingInstances[proposalId].AmountToExecutioner);
        } else {
            // TO DO Execution (or lack of)
            VotingInstances[proposalId].Passed = 2;
//            FakeDAO(DAO).ExecuteCoreProposal(proposalId, false); //turn into interface

            emit ProposalNotPassed(msg.sender, proposalId, VotingInstances[proposalId].AmountToBurn, VotingInstances[proposalId].AmountToExecutioner);
        }

        VotingInstances[proposalId].Executed = true;
    }

    function WithdrawVoteTokens(uint256 proposalId) external {
        if (VotingInstances[proposalId].ActiveVoters > 0) {
            require(VotingInstances[proposalId].Executed, 
            'VotingSystemV1.WithdrawMyTokens: Proposal has not been executed!');
            _returnTokens(proposalId, msg.sender);
        } else {
            _returnTokens(proposalId, msg.sender);
        }

        emit IncentiveWithdrawed(VotingInstances[proposalId].IncentiveAmount);
    }

    function SetTaxAmount(uint256 amount, string memory taxToSet) public OnlyDAO returns (bool) {
        bytes32 _setHash = keccak256(abi.encodePacked(taxToSet));
        bytes32 _execusCut = keccak256(abi.encodePacked("execusCut"));
        bytes32 _burnCut = keccak256(abi.encodePacked("burnCut"));
        bytes32 _memberHolding = keccak256(abi.encodePacked("memberHolding"));

        if (_setHash == _execusCut || _setHash == _burnCut) {
            require(amount >= 10 && amount <= 10000, 
            "VotingSystemV1.SetTaxAmount: Percentages can't be higher than 100");
            ExecusCut = amount;
        } else if (_setHash == _memberHolding) {
            MemberHolding = amount;
        } else {
            revert("VotingSystemV1.SetTaxAmount: You didn't choose a valid setting to modify!");
        }

        return true;
    }

    function ChangeDAO(address newAddr) external OnlyDAO {
        require(DAO != newAddr, 
            "VotingSystemV1.ChangeDAO: New DAO address can't be the same as the old one");
        require(address(newAddr) != address(0), 
            "VotingSystemV1.ChangeDAO: New DAO can't be the zero address");
        DAO = newAddr;        
        emit NewDAOAddress(newAddr);
    }
    
    /////////////////////////////////////////
    /////        Internal functions     /////
    /////////////////////////////////////////

    // TO DO Refactor this
    function _returnTokens(
        uint256 _proposalId,
        address _voterAddr
        )
        internal {
        require(block.timestamp >= VotingInstances[_proposalId].VoteEnds, 
            "VotingSystemV1.WithdrawMyTokens: The voting period hasn't ended");

        if (VotingInstances[_proposalId].ActiveVoters > 0) {
            require(
                VoterInfo[_proposalId][_voterAddr].VotesLocked > 0, 
                "VotingSystemV1.WithdrawMyTokens: You have no VotesLocked in this proposal"
            );
            ERC20(CLD).transfer(_voterAddr, VoterInfo[_proposalId][_voterAddr].VotesLocked + VotingInstances[_proposalId].IncentiveShare);
            VotingInstances[_proposalId].IncentiveAmount -= VotingInstances[_proposalId].IncentiveShare; 
        } else {
            require(
                VoterInfo[_proposalId][_voterAddr].AmountDonated > 0, 
                "VotingSystemV1.WithdrawMyTokens: You have no AmountDonated in this proposal"
            );
            ERC20(CLD).transfer(_voterAddr, VoterInfo[_proposalId][_voterAddr].AmountDonated);
            VoterInfo[_proposalId][_voterAddr].AmountDonated -= VoterInfo[_proposalId][_voterAddr].AmountDonated;
            VotingInstances[_proposalId].IncentiveAmount -= VoterInfo[_proposalId][_voterAddr].AmountDonated;
        }
        
        VoterInfo[_proposalId][_voterAddr].VotesLocked -= VoterInfo[_proposalId][_voterAddr].VotesLocked;
    }

    function _updateTaxesAndIndIncentive(uint256 _proposalId, bool allOfThem) internal  {
        if (allOfThem) {            
            uint256 newBurnAmount = VotingInstances[_proposalId].IncentiveAmount * BurnCut / 10000;
            VotingInstances[_proposalId].AmountToBurn = newBurnAmount;

            uint newToExecutAmount = VotingInstances[_proposalId].IncentiveAmount * ExecusCut / 10000;
            VotingInstances[_proposalId].AmountToExecutioner = newToExecutAmount;

            _updateIncentiveShare(_proposalId, VotingInstances[_proposalId].IncentiveAmount);
        } else {
            _updateIncentiveShare(_proposalId, VotingInstances[_proposalId].IncentiveAmount);
        }

    }

    function _updateIncentiveShare(uint256 _proposalId, uint256 _baseTokenAmount) internal {
        uint256 totalTokenAmount = _baseTokenAmount - (VotingInstances[_proposalId].AmountToBurn + VotingInstances[_proposalId].AmountToExecutioner);
        if (VotingInstances[_proposalId].ActiveVoters > 0) {
            VotingInstances[_proposalId].IncentiveShare = totalTokenAmount / VotingInstances[_proposalId].ActiveVoters;
        } else {
            VotingInstances[_proposalId].IncentiveShare = totalTokenAmount;
        }
    }

    /////////////////////////////////////////
    /////          Debug Tools          /////
    /////////////////////////////////////////

    function viewVoterInfo(
        address voter, 
        uint256 proposalId
        ) 
        external view returns (
        uint256,
        uint256,  
        bool 
    ) 
    {
        return (
            VoterInfo[proposalId][voter].VotesLocked,
            VoterInfo[proposalId][voter].AmountDonated,
            VoterInfo[proposalId][voter].Voted
        );
    }
}

    /////////////////////////////////////////
    /////          Interfaces           /////
    /////////////////////////////////////////

interface ERC20 {
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 value) external returns (bool);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool); 
  function totalSupply() external view returns (uint256);
  function Burn(uint256 _BurnAmount) external;
}