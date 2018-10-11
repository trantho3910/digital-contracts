/**
 * Created on 2018-08-13 10:31
 * @summary: 
 * @author: Chris Nguyen
 */
pragma solidity ^0.4.24;
import './BBFreelancer.sol';
import './BBFreelancerPayment.sol';
import './BBLib.sol';
import './BBRatingInterface.sol';


/**
 * @title BBFreelancerJob
 */
contract BBFreelancerJob is BBFreelancer, BBRatingInterface {
   BBFreelancerPayment public payment = BBFreelancerPayment(0x0);

  /**
   * @dev 
   * @param paymentAddress address of the Payment Contract
   */
  function setPaymentContract(address paymentAddress) onlyOwner public {
    payment = BBFreelancerPayment(paymentAddress);
  }

  event JobCreated(bytes jobHash, uint256 jobID, address indexed owner, uint expired, bytes32 indexed category, uint256  budget, uint256 estimateTime);
  event JobCanceled(bytes jobHash);
  event JobStarted(bytes jobHash);
  event JobFinished(bytes jobHash);

  /**
   * @dev 
   * @param jobHash Job Hash
   */
  function getJob(bytes jobHash) public view returns(address, uint256, uint256, bool, uint256, address){
    address owner = bbs.getAddress(keccak256(jobHash));
    uint256 expired = bbs.getUint(BBLib.toB32(jobHash, 'EXPIRED'));
    uint256 budget = bbs.getUint(BBLib.toB32(jobHash, 'BUDGET'));
    bool cancel = bbs.getBool(BBLib.toB32(jobHash, 'CANCEL'));
    uint256 status = bbs.getUint(BBLib.toB32(jobHash, 'STATUS'));
    address freelancer = bbs.getAddress(BBLib.toB32(jobHash, 'FREELANCER'));
    return (owner, expired, budget, cancel, status, freelancer);

  }


  /**
   * @dev 
   * @param jobHash Job Hash
   * @param expired Time
   * @param estimateTime Time do the job
   * @param budget Buget
   * @param category Tag category
   */
  function createJob(bytes jobHash, uint expired ,uint estimateTime, uint256 budget, bytes32 category) public 
  jobNotExist(jobHash)
  {
    // check jobHash not null
    require(jobHash.length > 0);
    // expired > now
    require(expired > now);
    // budget
    require(budget > 0);

    require(estimateTime > 0);

    // save jobHash owner
    bbs.setAddress(keccak256(jobHash), msg.sender);
    // save expired timestamp
    bbs.setUint(BBLib.toB32(jobHash, 'EXPIRED'), expired);
    //Save jobHash by jobID
    uint256 jobID = bbs.getUint(BBLib.toB32('JOB_ID'));
    jobID++;
    bbs.setUint(BBLib.toB32('JOB_ID'),jobID);

    bbs.setBytes(BBLib.toB32(jobID), jobHash);
    // save time freelancer can done this job
    bbs.setUint(BBLib.toB32(jobHash, 'ESTIMATE_TIME'), estimateTime);
    // save budget 
    bbs.setUint(BBLib.toB32(jobHash, 'BUDGET'), budget);
 
    emit JobCreated(jobHash, jobID, msg.sender, expired, category, budget, estimateTime);
  }
    // hirer  cancel job
  /**
   * @dev 
   * @param jobHash Job Hash
   */
  function cancelJob(bytes jobHash) public 
  isOwnerJob(jobHash)  {

    uint status = bbs.getUint(BBLib.toB32(jobHash,'STATUS'));
    require(status == 0 || status == 1);
    if(status == 1) {
      address freelancer = bbs.getAddress(BBLib.toB32(jobHash, 'FREELANCER'));
      uint bidTime = bbs.getUint(BBLib.toB32(jobHash, 'BID_TIME', freelancer));
      uint timeStartJob = bbs.getUint(BBLib.toB32(jobHash, 'JOB_STARTED_TIMESTAMP'));
      require(now > timeStartJob + bidTime);
    }
    bbs.setBool(BBLib.toB32(jobHash,'CANCEL'), true);
    require(payment.refundBBO(jobHash));
    emit JobCanceled(jobHash);
  }
  // freelancer start Job
  /**
   * @dev 
   * @param jobHash Job Hash
   */
  function startJob(bytes jobHash) public 
  isNotCanceled(jobHash)
  jobNotStarted(jobHash)
  isFreelancerOfJob(jobHash) {
    // set status to 1
    bbs.setUint(BBLib.toB32(jobHash,'STATUS'), 1);
    //Begin set time start job
    bbs.setUint(BBLib.toB32(jobHash,'JOB_STARTED_TIMESTAMP'), now);
    
    emit JobStarted(jobHash);
  }
  // freelancer finish Job
  /**
   * @dev 
   * @param jobHash Job Hash
   */
  function finishJob(bytes jobHash) public 
  isNotOwnerJob(jobHash) 
  isFreelancerOfJob(jobHash) {
    //status el 1
    require(bbs.getUint(BBLib.toB32(jobHash,'STATUS')) ==1);

    bbs.setUint(BBLib.toB32(jobHash,'STATUS'), 2);
    bbs.setUint(BBLib.toB32(jobHash,'JOB_FINISHED_TIMESTAMP'), now);
    emit JobFinished(jobHash);
  }

  function allowRating(address sender ,uint256 jobID) public view returns(bool r) {
    bytes memory jobHash = bbs.getBytes(keccak256(abi.encodePacked(jobID)));
    address jobOwner = bbs.getAddress(BBLib.toB32(jobHash));
    address freelancer = bbs.getAddress(BBLib.toB32(jobHash, 'FREELANCER'));
    r = (sender == jobOwner || sender == freelancer);
    if(r == true) {
      uint256 jobStatus = bbs.getUint(BBLib.toB32(jobHash ,'STATUS'));
      r = (jobStatus == 5 || jobStatus == 9);
    }
  }

    function getRelatedTo(address sender, uint256 jobID) public view returns (bytes32) {
        bytes memory jobHash = bbs.getBytes(keccak256(abi.encodePacked(jobID)));
        address jobOwner = bbs.getAddress(BBLib.toB32(jobHash));
        address freelancer = bbs.getAddress(BBLib.toB32(jobHash, 'FREELANCER'));

        if(sender == jobOwner) {
          return keccak256(abi.encodePacked(freelancer));
        }
        return keccak256(abi.encodePacked(jobOwner));
    }

      function getRating(address relatedAddress, uint256 jobID) public view returns (uint256, uint256, uint256, uint256) {

        bytes memory jobHash = bbs.getBytes(keccak256(abi.encodePacked(jobID)));
        address jobOwner = bbs.getAddress(BBLib.toB32(jobHash));
        address freelancer = bbs.getAddress(BBLib.toB32(jobHash, 'FREELANCER'));

        uint totalStarClient = bbs.getUint(keccak256(abi.encodePacked(relatedAddress, keccak256(abi.encodePacked(jobOwner)))));
        uint totalRateClient = bbs.getUint(keccak256(abi.encodePacked(relatedAddress, keccak256(abi.encodePacked(jobOwner)),'RATE')));

        uint totalStarFreelancer = bbs.getUint(keccak256(abi.encodePacked(relatedAddress, keccak256(abi.encodePacked(freelancer)))));
        uint totalRateFreelancer = bbs.getUint(keccak256(abi.encodePacked(relatedAddress, keccak256(abi.encodePacked(freelancer)),'RATE')));

        return (totalStarClient, totalRateClient, totalStarFreelancer, totalRateFreelancer);
      }



}
