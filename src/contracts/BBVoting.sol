  /**
 * Created on 2018-08-13 10:20
 * @summary: 
 * @author: Chris Nguyen
 */
pragma solidity ^0.4.24;

import './BBStandard.sol';
import './BBLib.sol';
import './BBVotingInterface.sol';
import './BBVotingHelper.sol';
/**
 * @title BBVoting contract 
 */
contract BBVoting is BBStandard{
  BBVotingHelper public helper = BBVotingHelper(0x0);
  function setHelper(address _helper) onlyOwner public {
    helper = BBVotingHelper(_helper);
  }

  event PollStarted(uint256 pollID, uint256 indexed pollType, address indexed creator, uint256 indexed relatedTo);
  event PollOptionAdded(uint256 indexed pollID, address indexed creator, bytes pollOption);
  event PollUpdated(uint256 indexed pollID,bool indexed whiteFlag);

  event VotingRightsGranted(address indexed voter, uint256 numTokens);
  event VotingRightsWithdrawn(address indexed voter, uint256 numTokens);
  event VoteCommitted(address indexed voter, uint256 indexed pollID);
  event VoteRevealed(address indexed voter, uint256 indexed pollID);
  
  /**
   * @dev request voting rights
   * 
   */
  function requestVotingRights(uint256 numTokens) public {
    require(bbo.balanceOf(msg.sender) >= numTokens);
    uint256 voteTokenBalance = bbs.getUint(BBLib.toB32(msg.sender,'STAKED_VOTE'));
    require(bbo.transferFrom(msg.sender, address(this), numTokens));
    bbs.setUint(BBLib.toB32(msg.sender,'STAKED_VOTE'), voteTokenBalance.add(numTokens));
    emit VotingRightsGranted(msg.sender, numTokens);
  }
  
  /**
   * @dev withdraw voting rights
   * 
   */
  function withdrawVotingRights(uint256 numTokens) public 
  {
    uint256 voteTokenBalance = bbs.getUint(BBLib.toB32(msg.sender,'STAKED_VOTE'));
    require (voteTokenBalance > 0);
    require (numTokens > 0);
    require (numTokens<= voteTokenBalance);
    bbs.setUint(BBLib.toB32(msg.sender,'STAKED_VOTE'), voteTokenBalance.sub(numTokens));
    require(bbo.transfer(msg.sender, numTokens));
    emit VotingRightsWithdrawn(msg.sender, numTokens);
  }


  /**
   * @dev commitVote for poll
   * @param pollID Job Hash
   * @param secretHash Hash of Choice address and salt uint
   */
  function commitVote(uint256 pollID, bytes32 secretHash, uint256 tokens) public 
  {
    //uint256 minVotes = bbs.getUint(keccak256('MIN_VOTES'));
    //uint256 maxVotes = bbs.getUint(keccak256('MAX_VOTES'));
    uint256 pollStatus = bbs.getUint(BBLib.toB32(pollID,'STATUS'));
    require(pollStatus == 1);
    //require(tokens >= minVotes);
    //require(tokens <= maxVotes);
    (uint256 addPollOptionEndDate,uint256 commitEndDate, ) = helper.getPollStage(pollID);
    
    require(addPollOptionEndDate<now);
    require(commitEndDate>now);
    require(secretHash != 0);
    
    uint256 voteTokenBalance = bbs.getUint(BBLib.toB32(msg.sender,'STAKED_VOTE'));
    if(voteTokenBalance<tokens){
      requestVotingRights(tokens.sub(voteTokenBalance));
    }
    require(bbs.getUint(BBLib.toB32(msg.sender,'STAKED_VOTE')) >= tokens);
    // add secretHash
    bbs.setBytes(BBLib.toB32(pollID ,'SECRET_HASH',msg.sender), abi.encodePacked(secretHash));
    bbs.setUint(BBLib.toB32(pollID ,'VOTES',msg.sender), tokens);
    if(bbs.getBool(BBLib.toB32(pollID, 'HAS_VOTE')) == false){
      bbs.setBool(BBLib.toB32(pollID, 'HAS_VOTE'), true); 
    }
    emit VoteCommitted(msg.sender, pollID);
  }


  /**
  * @dev revealVote for poll
  * @param pollID Job Hash
  * @param choice address 
  * @param salt salt
  */
  function revealVote(uint256 pollID, address choice, uint salt) public 
  {
    (,uint256 commitEndDate, uint256 revealEndDate) = helper.getPollStage(pollID);
    require(commitEndDate<now);
    require(revealEndDate>now);
    uint256 pollStatus = bbs.getUint(BBLib.toB32(pollID,'STATUS'));
    require(pollStatus == 1);
    uint256 voteTokenBalance = bbs.getUint(BBLib.toB32(msg.sender,'STAKED_VOTE'));
    uint256 votes = bbs.getUint(BBLib.toB32(pollID,'VOTES',msg.sender));
    // check staked vote
    require(voteTokenBalance>= votes);

    bytes32 choiceHash = BBLib.toB32(choice,salt);
    bytes32 secretHash = BBLib.bytesToBytes32(bbs.getBytes(BBLib.toB32(pollID,'SECRET_HASH',msg.sender)));
    require(choiceHash == secretHash);
    uint256 numVote = bbs.getUint(BBLib.toB32(pollID,'VOTE_FOR',choice));
    //save result poll
    bbs.setUint(BBLib.toB32(pollID,'VOTE_FOR',choice), numVote.add(votes));
    // save voter choice
    bbs.setAddress(BBLib.toB32(pollID,'CHOICE',msg.sender), choice);
    emit VoteRevealed(msg.sender, pollID);
  }


  function updatePoll(uint256 pollID, bool whiteFlag) public {
    (uint256 pollStatus, uint256 pollType, uint256 relatedTo,,address relatedAddr, bool hasVote) = helper.getPollDetail(pollID);
    (,uint256 commitEndDate,uint256 revealEndDate) = helper.getPollStage(pollID);
    (, uint256 commitDuration,uint256 revealDuration,) = helper.getPollParams(pollType);
    require(pollStatus == 1);
    require(allowVoting( relatedAddr,  relatedTo));
    require(revealEndDate > now);
    require(hasVote== false);
    if(whiteFlag){
      return _doWhiteFlag(pollID);
    }else{
      require(commitEndDate < now);
      return _doExtendPoll(pollID, commitDuration, revealDuration);
    }
  }
  function _doWithdrawStakeToken(uint256 pollID) private returns(bool){
    uint256 stakedBBO = bbs.getUint(BBLib.toB32(pollID,'STAKED_DEPOSIT',msg.sender));
    if(stakedBBO > 0){
      bbs.setUint(BBLib.toB32(pollID,'STAKED_DEPOSIT',msg.sender), 0);
      require(bbo.transfer(msg.sender, stakedBBO));
      return true;
    }
    return false;
  }
  function _doWhiteFlag(uint256 pollID) private {
    assert(_doWithdrawStakeToken(pollID));
    bbs.deleteBytes(BBLib.toB32(pollID, 'POLL_OPTION', msg.sender));
    emit PollUpdated(pollID, true );
  }
  function _doExtendPoll(uint256 pollID, uint256 commitDuration,uint256 revealDuration) private {
    bbs.setUint(BBLib.toB32(pollID,'COMMIT_ENDDATE'), block.timestamp.add(commitDuration));
    bbs.setUint(BBLib.toB32(pollID,'REVEAL_ENDDATE'), block.timestamp.add(commitDuration).add(revealDuration));
    emit PollUpdated(pollID, false);
  }

  function allowVoting(address relatedAddr, uint256 relatedTo) private returns(bool c){
     return BBVotingInterface(relatedAddr).allowVoting(msg.sender, relatedTo);
  }
  function startPoll(uint256 pollType, uint256 relatedTo, bytes extraData) public {
    address relatedAddr = bbs.getAddress(BBLib.toB32('POLL_RELATED', pollType));
    // make sure the voting having the allowVoting method :v 
    require(allowVoting(relatedAddr,relatedTo));
    require(helper.hasVoting(pollType, relatedTo)!=true);
    //TODO
    return _doStartPoll(pollType, relatedTo, extraData);
  }
  function _doStartPoll(uint256 pollType, uint256 relatedTo, bytes extraData) private {
    //TODO
    (uint256 addOptionDuration, uint256 commitDuration,uint256 revealDuration, uint256 bboStake) = helper.getPollParams(pollType);
    // get current ID
    uint256 latestID  = bbs.getUint(BBLib.toB32('POLL_COUNTER'));
    uint256 pollID = latestID + 1;
    bbs.setUint(BBLib.toB32('POLL_COUNTER'), pollID);
    assert(_doStakeToken( pollID, bboStake));
    // save startPoll address
    bbs.setAddress(BBLib.toB32(pollID, 'POLL_STARTED'), msg.sender);
    
    // addPollOptionEndDate
    uint256 addPollOptionEndDate = block.timestamp.add(addOptionDuration);
    // commitEndDate
    uint256 commitEndDate = addPollOptionEndDate.add(commitDuration);
    // revealEndDate
    uint256 revealEndDate = commitEndDate.add(revealDuration);
    // save addPollOption, commit, reveal EndDate
    bbs.setUint(BBLib.toB32(pollID,'STATUS'), 1);
    bbs.setUint(BBLib.toB32(pollID,'ADDOPTION_ENDDATE'), addPollOptionEndDate);
    bbs.setUint(BBLib.toB32(pollID,'COMMIT_ENDDATE'), commitEndDate);
    bbs.setUint(BBLib.toB32(pollID,'REVEAL_ENDDATE'), revealEndDate);
    // save relatedTo
    bbs.setUint(BBLib.toB32(pollID,'RELATED_TO'), relatedTo);
    bbs.setUint(BBLib.toB32(pollID,'POLL_TYPE'), pollType);
    // save pollID to relatedTo
    bbs.setUint(BBLib.toB32(relatedTo, pollType,'POLL'), pollID);

    _doAddPollOption( pollID, msg.sender, extraData);

    emit PollStarted(pollID, pollType, msg.sender, relatedTo);

  }
  
  function addPollOption(uint256 pollID, bytes pollOption) public {
    (uint256 pollStatus,, uint256 relatedTo,address creator,address relatedAddr,) = helper.getPollDetail(pollID);
    require(pollStatus == 1);
    require(allowVoting(relatedAddr, relatedTo));
    require(bbs.getUint(BBLib.toB32(pollID,'ADDOPTION_ENDDATE')) > now);
    return _doAddPollOption(pollID, creator, pollOption);
  }
  function _doStakeToken(uint256 pollID, uint256 bboStake) private returns(bool) {
    uint256 stakedBBO = bbs.getUint(BBLib.toB32(pollID,'STAKED_DEPOSIT',msg.sender));
    if(bboStake.sub(stakedBBO) > 0){
      require(bbo.transferFrom(msg.sender, address(this), bboStake.sub(stakedBBO)));
      bbs.setUint(BBLib.toB32(pollID,'STAKED_DEPOSIT',msg.sender), bboStake);
    }
    return true;
  }
  
  function _doAddPollOption(uint256 pollID, address creator, bytes pollOption) private {
    uint256 bboStake = bbs.getUint(BBLib.toB32(pollID,'STAKED_DEPOSIT',creator));
    assert(_doStakeToken(pollID, bboStake));
    if(BBLib.toB32(bbs.getBytes(BBLib.toB32(pollID, 'POLL_OPTION', msg.sender)))!=BBLib.toB32(''))
    {
      //update pollOption
      bbs.setBytes(BBLib.toB32(pollID, 'POLL_OPTION', msg.sender), pollOption);
    }else{
      //add address sender
      uint256 numOption = bbs.getUint(BBLib.toB32(pollID, 'NUM_OPTION'));
      require(numOption < 10);
      bbs.setUint(BBLib.toB32(pollID, 'NUM_OPTION'), numOption.add(1));
      bbs.setAddress(BBLib.toB32(pollID, 'OPTION_CREATOR', numOption.add(1)), msg.sender);
      bbs.setBytes(BBLib.toB32(pollID, 'POLL_OPTION', msg.sender), pollOption);
    } 
    emit PollOptionAdded(pollID, msg.sender, pollOption);
  }
  
}
