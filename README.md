# AME Chain Staking Contract

## Overview
This is a Solidity smart contract for staking, developed by AME Chain. It allows users to stake tokens (both native and ERC20) in various pools to earn rewards based on an Annual Percentage Rate (APR). The contract includes features for pool management, staking/unstaking operations, and reward calculations, with security features like ownership control and reentrancy protection.

- **Version**: 1.3.0
- **License**: MIT
- **Solidity Version**: ^0.8.0
- **Dependencies**: OpenZeppelin's `Ownable`, `SafeERC20`, and `ReentrancyGuard`

## Features
- **Flexible Pool Management**: Create and manage staking pools with customizable APR and lock durations.
- **Native and ERC20 Token Support**: Stake either native blockchain tokens or ERC20 tokens.
- **Reward System**: Earn rewards based on APR and staking duration, calculated with high precision.
- **Locking Mechanism**: Supports locked staking with configurable durations.
- **Unstake Requests**: Users can request to unstake, with a manager-controlled completion process.
- **Batch Processing**: Efficiently process multiple unstake requests in a single transaction.
- **Security**: Uses OpenZeppelin's libraries for secure token transfers and reentrancy protection.
- **Pagination**: Retrieve pools, user stakes, and unstake requests with offset and limit for scalability.
- **Manager Role**: Restricted actions for pool management and unstake processing.

## Contract Structure

### Key Structs
- **Pool**: Defines a staking pool with properties like `poolId`, `isNative`, `token`, `apr`, `lockDuration`, and `isActive`.
- **StakingDetails**: Tracks user stakes with details like `stakedAmount`, `startTime`, `poolId`, `lockDuration`, `rewardsEarned`, and `status`.
- **StakingUserData**: User-friendly stake data for frontend display.
- **UnstakeRequest**: Manages unstake requests with details like `requestId`, `user`, `stakeIndex`, `amount`, `reward`, `timestamp`, and `status`.

### Key Variables
- `minimumStakeDuration`: Minimum duration a stake must be held.
- `minimumStakeAmount`: Minimum amount required to stake (default: 1 * 10^18).
- `treasury`: Address where staked tokens are transferred.
- `poolCount`: Tracks the total number of pools.
- Mappings for pools, user stakes, unstake requests, and manager roles.

### Events
- `Staked`: Emitted when a user stakes tokens.
- `UnstakeRequested`: Emitted when a user requests to unstake.
- `RequestCompleted`: Emitted when an unstake request is completed.
- `PoolCreated`: Emitted when a new pool is created.
- `PoolUpdated`: Emitted when a pool's status is updated.
- `BatchUnstakeProcessed`: Emitted when multiple unstake requests are processed.
- `MinimumStakeDurationUpdated`, `MinimumStakeAmountUpdated`, `TreasuryUpdated`, `ManagerUpdated`: Emitted for configuration changes.

## Installation and Deployment
1. **Prerequisites**:
   - Install [Node.js](https://nodejs.org/) and [Hardhat](https://hardhat.org/) or [Truffle](https://www.trufflesuite.com/) for deployment.
   - Ensure you have a compatible Ethereum wallet (e.g., MetaMask).
   - Install OpenZeppelin contracts:
     ```bash
     npm install @openzeppelin/contracts
     ```

2. **Compile the Contract**:
   ```bash
   npx hardhat compile
   ```

3. **Deploy the Contract**:
   - Configure your deployment script (e.g., in Hardhat) with the network settings.
   - Deploy using:
     ```bash
     npx hardhat run scripts/deploy.js --network <network-name>
     ```

4. **Contract Initialization**:
   - The constructor sets the deployer as the owner and initial manager, with a default `minimumStakeAmount` of 1 * 10^18 and `treasury` address.

## Usage
1. **Create a Pool**:
   - Call `createPool(_isNative, _token, _apr, _lockDuration)` as a manager to create a staking pool.
   - Example: Create a native token pool with 5% APR and 30-day lock:
     ```solidity
     createPool(true, address(0), 5, 30 days);
     ```

2. **Stake Tokens**:
   - Call `stake(_poolId, _amount)` with the appropriate amount (and native token value for native pools).
   - Example: Stake 10 tokens in pool ID 0:
     ```solidity
     stake(0, 10 * 10**18);
     ```

3. **Request Unstake**:
   - Call `requestUnstake(_stakeIndex)` after the lock duration to initiate unstaking.
   - Example: Request unstake for stake index 0:
     ```solidity
     requestUnstake(0);
     ```

4. **Complete Unstake**:
   - Managers call `completeUnstake(_poolId, _requestIndex)` or `batchCompleteUnstake(_poolId, _requestIndices)` to process unstake requests and transfer funds.

5. **View Data**:
   - Use `getActivePools`, `getAllPools`, `getUserStakes`, or `getUnstakeRequests` to retrieve pool or stake information with pagination.

## Security Considerations
- **Reentrancy Protection**: Uses `ReentrancyGuard` to prevent reentrancy attacks.
- **Safe Token Transfers**: Leverages `SafeERC20` for secure ERC20 token operations.
- **Access Control**: Manager and owner roles restrict sensitive operations.
- **Input Validation**: Ensures valid pool IDs, amounts, and durations.
- **Precision Handling**: Uses a high precision factor (1e6) for accurate reward calculations.

## Testing
- Write test cases using Hardhat or Truffle to cover:
  - Pool creation and updates.
  - Staking and unstaking workflows.
  - Reward calculations.
  - Edge cases (e.g., invalid inputs, zero balances).
- Example test framework:
  ```bash
  npx hardhat test
  ```

## Contributing
- Fork the repository and submit pull requests for improvements.
- Follow Solidity best practices and include tests for new features.
- Contact AME Chain for collaboration or inquiries.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact
- **Author**: AME Chain
- **GitHub**: [Link to your repository]
- **Support**: [Your support email or website]