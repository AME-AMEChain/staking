// Author : AME Chain
// Version : 1.3.0
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Staking Contract
 * @dev This contract allows users to stake tokens in various pools, earning rewards over time.
 * It supports both native tokens and ERC20 tokens.
 */
contract Staking is Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    enum Status { Staked , Pending, Completed }

// --------------------- STRUCTS ---------------------

    /// @dev Stores details of a staking pool
    struct Pool {
        uint256 poolId;         // Unique Pool Identifier
        bool isNative;          // Indicates if the pool uses native coins or ERC20 token
        IERC20 token;           // ERC20 token contract address (address(0) for native)
        uint256 apr;            // Annual Percentage Rate for rewards
        uint256 lockDuration;   // Duration in seconds for locked staking
        bool isActive;          // Pool activation status
    }

    /// @dev Stores details of a user's stake
    struct StakingDetails {
        uint256 stakedAmount;   // Amount staked by the user
        uint256 startTime;      // Timestamp when stake was created
        uint256 poolId;         // ID of the pool
        uint256 lockDuration;   // Duration in seconds for locked staking
        uint256 rewardsEarned;  // Accumulated rewards
        Status status;          // Current status of the stake
    }

    /// @dev Stores user-friendly data of a user's stake
    struct StakingUserData {
        uint256 stakeId;        // Index of the user's stake
        uint256 amount;         // Amount staked
        uint256 startTime;      // Stake start timestamp
        uint256 endTime;        // Stake end timestamp (if locked)
        uint256 poolId;         // Pool ID
        uint256 apr;            // APR of the pool
        uint256 lockDuration;   // Lock duration of the pool
        bool isNative;          // Whether the pool uses native coins or ERC20
        IERC20 token;           // Pool's token contract
        uint256 rewardsEarned;  // Rewards earned
        Status status;          // Current status of the stake
    }

    /// @dev Stores unstake request details
    struct UnstakeRequest {
        uint256 requestId;      // Unique request Identifier
        address user;           // User who made the request
        uint256 stakeIndex;     // Index of the stake
        uint256 amount;         // Staked amount
        uint256 reward;         // Reward amount
        uint256 timestamp;      // Timestamp of the request
        Status status;          // Current status of the stake
    }
// --------------------- STATE VARIABLES -------------

    uint256 private constant SECONDS_IN_YEAR = 365 days;        // Seconds in a year for APR calculations
    uint256 private constant PRECISION = 1e6;                   // Precision factor for calculations
    uint256 public minimumStakeDuration;                        // Minimum duration a stake must be held
    uint256 public minimumStakeAmount;                          // Minimum Amount a stake must be have
    uint256 private poolCount;                                  // Counter for pool IDs
    address public treasury;                                    // Treasury address to receive staked tokens

    // Mappings
    mapping(uint256 => Pool) private pools;                                         // Mapping of pool ID to pool details
    mapping(address => bool) private managers;                                      // Contract Managers
    mapping(address => mapping(uint256 => StakingDetails)) private userStakes;      // Mapping of user address to stake index to stake details
    mapping(address => uint256) private userStakeCount;                             // Mapping of user address to their total stake count
    mapping(uint256 => uint256) public totalStakedPerPool;                          // Mapping of pool ID to total staked amount in the pool
    mapping(uint256 => mapping(uint256 => UnstakeRequest)) private unstakeRequests; // Mapping of pool ID to request ID to unstake request details
    mapping(uint256 => uint256) public unstakeRequestCount;                       // poolId => requestId counter
    
// --------------------- EVENTS ----------------------
    event Staked(address indexed user, uint256 amount, uint256 poolId, uint256 stakeIndex, uint256 timestamp);
    event UnstakeRequested(address indexed user, uint256 poolId, uint256 stakeIndex, uint256 amount, uint256 reward, uint256 timestamp);
    event RequestCompleted(address indexed user, uint256 poolId, uint256 stakeIndex, uint256 requestIndex, uint256 amount, uint256 timestamp);
    event PoolCreated(uint256 indexed poolId, uint256 apr, uint256 lockDuration, uint256 timestamp);
    event PoolUpdated(uint256 indexed poolId, bool isActive, uint256 timestamp);
    event BatchUnstakeProcessed(uint256 indexed poolId,uint256 requestsProcessed, uint256 timestamp);
    event MinimumStakeDurationUpdated(uint256 oldDuration, uint256 newDuration, uint256 timestamp);
    event MinimumStakeAmountUpdated(uint256 oldAmount, uint256 newAmount, uint256 timestamp);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury, uint256 timestamp);
    event ManagerUpdated(address indexed manager, bool status, uint256 timestamp);
// --------------------- CONSTRUCTOR -----------------
    constructor() Ownable() {
        minimumStakeDuration = 0;
        minimumStakeAmount = 1 * 10**18;
        treasury = 0x2c53F4bEDCDb29D73cfA062Ac9F8ADb5CCdBf9Ec;
        managers[msg.sender] = true;
    }     

// --------------------- MODIFIERS -------------------
    modifier validPool(uint256 _poolId) {
        require(_poolId < poolCount, "Invalid pool ID");
        require(pools[_poolId].isActive, "Pool is not active");
        _;
    }

    modifier isManager(){
        require(managers[msg.sender] == true, "Not an Manager");
        _;
    }

// --------------------- POOL MANAGEMENT -------------
    /// @notice Creates a new staking pool
    /// @param _isNative Whether the pool uses native coin
    /// @param _token ERC20 token address (address(0) for native)
    /// @param _apr Annual Percentage Rate for rewards
    /// @param _lockDuration Duration in seconds for locked staking
   function createPool(bool _isNative, address _token, uint256 _apr, uint256 _lockDuration) external nonReentrant isManager {
        require((_isNative && _token == address(0)) || (!_isNative && _token != address(0)), "Invalid token");
        require(_apr > 0, "APR must be greater than 0");
        require(_lockDuration >= 0 , "Invalid Lock Duration");
        pools[poolCount] = Pool({
            poolId : poolCount,
            isNative: _isNative,
            token: IERC20(_token),
            apr: _apr,
            lockDuration: _lockDuration,
            isActive: true
        });

        emit PoolCreated(poolCount, _apr, _lockDuration, block.timestamp);
        poolCount++;
    }

    /// @notice Updates the status of a pool
    /// @param _poolId ID of the pool to update
    /// @param _isActive New status of the pool
    function updatePoolStatus(uint256 _poolId, bool _isActive) external isManager {
        require(_poolId < poolCount, "Invalid pool ID");
        pools[_poolId].isActive = _isActive;
        emit PoolUpdated(_poolId, _isActive, block.timestamp);
    }

    /// @notice Retrieves all active pools
    /// @param offset Starting index to search for active pools
    /// @param limit Maximum number of active pools to return
    /// @return Array of active pool details
    function getActivePools(uint256 offset, uint256 limit) external view returns (Pool[] memory) {
        
        Pool[] memory temp = new Pool[](limit);
        uint256 count;
        uint256 found;

        for (uint256 i = 0; i < poolCount && count < offset + limit ; i++) {
            if (pools[i].isActive) {
                if (count >= offset) {
                    temp[found] = pools[i];
                    found++;
                }
                count++;
            }
        }

        Pool[] memory activePools = new Pool[](found);
        for (uint256 i = 0; i < found; i++) {
            activePools[i] = temp[i];
        }

        return activePools;
    }


    /// @notice Retrieves all pools with pagination
    /// @param offset Starting index
    /// @param limit Maximum number of pools to return
    /// @return Array of pool details
    function getAllPools(uint256 offset, uint256 limit) external view returns (Pool[] memory) {
        
        require(offset<= poolCount,"Invalid Offset");

        uint256 end = offset + limit > poolCount ? poolCount : offset + limit;
        uint256 size = end - offset;

        Pool[] memory result = new Pool[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = pools[offset + i];
        }

        return result;
    }

    /// @notice Returns the total number of pools
    /// @return Total pool count
    function getPoolCount() external view returns (uint256) {
        return poolCount;
    }


// --------------------- STAKING OPERATIONS ----------
    /// @notice Allows a user to stake tokens in a pool
    /// @param _poolId ID of the pool to stake in
    /// @param _amount Amount to stake
    function stake(uint256 _poolId, uint256 _amount) external payable nonReentrant validPool(_poolId) {
        require(_amount >= minimumStakeAmount, "Invalid Stake Amount");
        Pool memory pool = pools[_poolId];

        if (pool.isNative) {
            require(msg.value == _amount, "Incorrect amount");
            payable(treasury).transfer(_amount);
        } else {
            require(msg.value == 0, "No Native Coin needed");
            pool.token.safeTransferFrom(msg.sender, treasury, _amount);
        }

        uint256 stakeIndex = userStakeCount[msg.sender];
        userStakes[msg.sender][stakeIndex] = StakingDetails({
            stakedAmount: _amount,
            startTime: block.timestamp,
            lockDuration : pool.lockDuration,
            poolId: _poolId,
            rewardsEarned: 0,
            status: Status.Staked
        });

        userStakeCount[msg.sender]++;
        totalStakedPerPool[_poolId] += _amount;

        emit Staked(msg.sender, _amount, _poolId, stakeIndex, block.timestamp);
    }

    /// @notice Requests to unstake tokens
    /// @param _stakeIndex Index of the stake to unstake
    function requestUnstake(uint256 _stakeIndex) external nonReentrant {
        require(_stakeIndex < userStakeCount[msg.sender], "Invalid stake index");
        StakingDetails storage stakeData = userStakes[msg.sender][_stakeIndex];
        require(stakeData.status == Status.Staked, "Stake not active");
        require(block.timestamp >= stakeData.startTime + stakeData.lockDuration + minimumStakeDuration, "Stake still locked");// enforce minimum stake duration of variable

        uint256 reward = calculateReward(msg.sender, _stakeIndex);
        stakeData.rewardsEarned = reward;
        stakeData.status = Status.Pending;

        uint256 requestId = unstakeRequestCount[stakeData.poolId]++;

        unstakeRequests[stakeData.poolId][requestId] = UnstakeRequest({
            requestId : requestId,
            user: msg.sender,
            stakeIndex: _stakeIndex,
            amount: stakeData.stakedAmount,
            reward: reward,
            timestamp: block.timestamp,
            status:Status.Pending
        });

        totalStakedPerPool[stakeData.poolId] -= stakeData.stakedAmount;

        emit UnstakeRequested(msg.sender, stakeData.poolId, _stakeIndex, stakeData.stakedAmount, reward, block.timestamp);
    }

    /// @notice Completes an unstake request and transfers rewards to the user
    /// @param _poolId Id of Requested Pool
    /// @param _requestIndex Index of the request
    function completeUnstake(uint256 _poolId, uint256 _requestIndex) external payable isManager nonReentrant {
        require(_requestIndex < unstakeRequestCount[_poolId],"Invalid Stake Index");
        require(_poolId < poolCount,"Invalid Pool Index");
        UnstakeRequest storage request = unstakeRequests[_poolId][_requestIndex];
        require(request.status == Status.Pending, "Request not pending");

        StakingDetails storage stakeData = userStakes[request.user][request.stakeIndex];
        require(stakeData.status == Status.Pending, "Request not pending");

        Pool memory pool = pools[stakeData.poolId];
        uint256 reward = stakeData.rewardsEarned;
        uint256 totalAmount = stakeData.stakedAmount + reward;
        
        stakeData.status = Status.Completed;
        request.status = Status.Completed;

        if (pool.isNative) {
            require(msg.value >= totalAmount, "Incorrect amount"); // can add precision
            payable(request.user).transfer(totalAmount);
        } else {
            require(pool.token.balanceOf(msg.sender) >= totalAmount, "Insufficient token balance");
            require(msg.value == 0, "No Native Coin needed");
            pool.token.safeTransferFrom(msg.sender, request.user, totalAmount);
        }

        emit RequestCompleted(request.user, stakeData.poolId, request.stakeIndex , _requestIndex, totalAmount, block.timestamp);
    }


    /// @notice Processes a batch of specific unstake requests for a given pool
    /// @param _poolId ID of the pool
    /// @param _requestIndices Array of request indices to process
    function batchCompleteUnstake(
        uint256 _poolId,
        uint256[] calldata _requestIndices
    ) external payable isManager nonReentrant {
        require(_poolId < poolCount, "Invalid Pool Index");
        require(_requestIndices.length > 0, "No requests provided");

        uint256 requestsProcessed = 0;
        uint256 totalEthRequired = 0;

        // First pass: Calculate total ETH required for native token pools
        for (uint256 i = 0; i < _requestIndices.length; i++) {
            uint256 requestIndex = _requestIndices[i];
            require(requestIndex < unstakeRequestCount[_poolId], "Invalid Request Index");
            UnstakeRequest storage request = unstakeRequests[_poolId][requestIndex];
            if (request.status == Status.Pending) {
                StakingDetails storage stakeData = userStakes[request.user][request.stakeIndex];
                if (stakeData.status == Status.Pending && pools[_poolId].isNative) {
                    totalEthRequired += stakeData.stakedAmount + stakeData.rewardsEarned;
                }
            }
        }

        // Check if sufficient ETH is provided for native token transfers
        require(msg.value >= totalEthRequired, "Insufficient amount");

        // Second pass: Process requests
        for (uint256 i = 0; i < _requestIndices.length; i++) {
            uint256 requestIndex = _requestIndices[i];
            UnstakeRequest storage request = unstakeRequests[_poolId][requestIndex];
            if (request.status != Status.Pending) {
                continue;
            }

            StakingDetails storage stakeData = userStakes[request.user][request.stakeIndex];
            if (stakeData.status != Status.Pending) {
                continue;
            }

            Pool memory pool = pools[stakeData.poolId];
            uint256 totalAmount = stakeData.stakedAmount + stakeData.rewardsEarned;

            stakeData.status = Status.Completed;
            request.status = Status.Completed;

            if (pool.isNative) {
                payable(request.user).transfer(totalAmount);
            } else {
                require(
                    pool.token.balanceOf(msg.sender) >= totalAmount,
                    "Insufficient token balance"
                );
                pool.token.safeTransferFrom(msg.sender, request.user, totalAmount);
            }

            emit RequestCompleted(
                request.user,
                stakeData.poolId,
                request.stakeIndex,
                requestIndex,
                totalAmount,
                block.timestamp
            );

            requestsProcessed++;
        }

        emit BatchUnstakeProcessed(_poolId, requestsProcessed, block.timestamp);
    }

// --------------------- REWARD MANAGEMENT -----------
    /// @notice Calculates the reward for a stake
    /// @param _user Address of the user
    /// @param _stakeIndex Index of the stake
    /// @return Calculated reward amount
    function calculateReward(address _user, uint256 _stakeIndex) private view returns (uint256) {
        require(_stakeIndex < userStakeCount[_user], "Invalid stake index");
        StakingDetails memory stakeData = userStakes[_user][_stakeIndex];
        if (stakeData.status != Status.Staked ) return stakeData.rewardsEarned;

        Pool memory pool = pools[stakeData.poolId];

        uint256 stakingDuration = block.timestamp - stakeData.startTime;
        if (stakeData.lockDuration > 0 && stakingDuration > stakeData.lockDuration) {
            stakingDuration = stakeData.lockDuration;
        } // Rewards Calculates till lock duration

        // Reward = (amount * APR * duration) / (100 * seconds_in_year)
        uint256 reward = (stakeData.stakedAmount * pool.apr * stakingDuration * PRECISION) / (100 * SECONDS_IN_YEAR * PRECISION);
        return reward;
    }

// --------------------- UTILITY FUNCTIONS -----------

    /// @notice Updates the Minimum Stake Duration 
    /// @param _minDuration New Minimum Stake Duration 
    function setMinimumStakeDuration(uint256 _minDuration) external isManager nonReentrant {
        require(_minDuration >= 0, "Invalid Duration");
        uint256 oldDuration = minimumStakeDuration;
        minimumStakeDuration = _minDuration;
        emit MinimumStakeDurationUpdated(oldDuration, _minDuration, block.timestamp);
    }

    /// @notice Updates the Minimum Stake Amount 
    /// @param _minAmount New Minimum Stake Amount 
    function setMinimumStakeAmount(uint256 _minAmount) external isManager nonReentrant {
        require(_minAmount >= 0, "Invalid Amount");
        uint256 oldAmount = minimumStakeAmount;
        minimumStakeAmount = _minAmount;
        emit MinimumStakeAmountUpdated(oldAmount, _minAmount, block.timestamp);
    }

    /// @notice Updates the mini address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external isManager nonReentrant {
        require(_treasury != address(0), "Invalid treasury address");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury, block.timestamp);
    }

    /// @notice Adds or removes a manager.
    /// @param _manager Address of the manager to be added or removed.
    /// @param status True to add the manager, false to remove the manager.
    function  manageManager(address _manager, bool status) external onlyOwner nonReentrant {
        managers[_manager] = status;
        emit ManagerUpdated(_manager, status, block.timestamp);
    }

    /// @notice Checks if the given address is a manager.
    /// @param _manager The address to verify.
    /// @return True if the address is a verified manager, false otherwise.
    function  verifyManager(address _manager) external view returns(bool){
        return managers[_manager];
    }


    /// @notice Retrieves a paginated list of stakes for a user
    /// @param _user Address of the user
    /// @param offset Starting index of the stakes to return
    /// @param limit Maximum number of stakes to return
    /// @return Array of user stake details
    function getUserStakes(address _user, uint256 offset, uint256 limit) external view returns (StakingUserData[] memory) {

        uint256 start = offset;
        uint256 end = offset + limit > userStakeCount[_user] ? userStakeCount[_user] : offset + limit;
        uint256 size = end - start;

        StakingUserData[] memory stakes = new StakingUserData[](size);

        for (uint256 i = 0; i < size; i++) {
            uint256 stakeIndex = offset + i;
            StakingDetails memory stakeData = userStakes[_user][stakeIndex];
            Pool memory pool = pools[stakeData.poolId];
            uint256 reward = calculateReward(_user, stakeIndex);
            uint256 endTime = stakeData.lockDuration > 0 ? stakeData.startTime + stakeData.lockDuration : 0;
            
            stakes[i] = StakingUserData({
                stakeId: stakeIndex,              
                amount: stakeData.stakedAmount,
                startTime: stakeData.startTime,
                endTime: endTime,
                poolId: stakeData.poolId,       
                apr: pool.apr,
                lockDuration: stakeData.lockDuration,
                isNative: pool.isNative,
                token: pool.token,
                rewardsEarned: reward,
                status: stakeData.status
            });
        }
        return stakes;
    }

    /// @notice Returns the total number of stakes by a user
    /// @param _user Address of the user
    /// @return Total number of user stakes
    function getUserTotalStakes(address _user) external view returns (uint256) {
        return userStakeCount[_user];
    }

    /// @notice Retrieves unstake requests
    /// @param poolId starting index_poolId
    /// @param offset starting index
    /// @param limit  number of requests
    /// @return Array of unstake request details
    function getUnstakeRequests(uint256 poolId , uint256 offset, uint256 limit) external view returns (UnstakeRequest[] memory) {
        
        uint256 requestCount = unstakeRequestCount[poolId];
        require(poolId < poolCount, "Invalid pool ID");
        require(offset < requestCount, "Offset out of bounds");

        uint256 end = offset + limit > requestCount ? requestCount : offset + limit;
        uint256 size = end - offset;

        UnstakeRequest[] memory requests = new UnstakeRequest[](size);

        for (uint256 i = 0; i < size; i++) {
            requests[i] = unstakeRequests[poolId][offset + i];
        }
        return requests;
    }

    /// @notice Withdraws excess funds from contract
    function withdrawExcessFunds() external isManager nonReentrant {
        uint256 contractBalance = address(this).balance;
        (bool sent, ) = msg.sender.call{value: contractBalance}("");
        require(sent, "Failed to send Balance");
    }

}