pragma solidity 0.8.0;

import "./IERC20.sol";

contract Masterchef{

  struct Pool {
    uint256 allocPoints;
    address lpToken;
    uint256 lastRewardBlock;
    uint256 accRewardPerShare;
  }

  struct User {
    uint256 amount;
    uint256 rewardWriteOff;
  }

  Pool[] public pools;
  mapping(uint256 => mapping(address => User)) users;

  address public owner;
  uint256 totalAllocPoints;
  uint256 sushiPerBlock;
  uint256 startBlock;
  uint256 bonusEndBlock;
  IERC20 sushi;

  // increases reward for early pool stakers
  uint256 BONUS_MULTIPLIER = 1e12;
  // used to improve precision
  uint256 CAL_MULTIPLIER;

  event PoolAdded (address lpToken, uint256 allocPoints);
  event PoolUpdated(address lpToken, uint256 reward);

  modifier onlyOwner() {
    require(owner == msg.sender, "NOT_OWNER");
    _;
  }

  constructor(uint256 _sushiPerBlock){
    sushiPerBlock = _sushiPerBlock;
    owner = msg.sender;
  }

  function addPool(address lpToken, uint256 allocPoints, bool withUpdate) onlyOwner external {
    if(withUpdate){
      updatePools();
    }
    require(lpToken != address(0), "ZERO_ADDRESS");
    totalAllocPoints += allocPoints;
    pools.push(Pool(allocPoints, lpToken, block.number >= startBlock ? block.number : startBlock, 0));

    emit PoolAdded(lpToken, allocPoints);
  }

  function updatePool(uint256 pId) public{
    Pool storage pool = pools[pId];

    if(pool.lastRewardBlock >= block.number){
      return;
    }
    uint256 lpTokenBalance = IERC20(pool.lpToken).balanceOf(address(this));
    if(lpTokenBalance == 0){
      pool.lastRewardBlock = block.number;
      return;
    }

    uint256 blockElapsed = _getMultiplier(pool.lastRewardBlock, block.number);
    uint256 poolReward = (blockElapsed * sushiPerBlock * pool.allocPoints) / totalAllocPoints;
    sushi.mint(address(this), poolReward);
 
    pool.accRewardPerShare += (poolReward * CAL_MULTIPLIER) / lpTokenBalance;
    pool.lastRewardBlock = block.number;

    emit PoolUpdated(pool.lpToken, poolReward);
  }

  function viewPendingRewards(uint256 pId, address userAddress) external view returns (uint256) {
    User memory user = users[pId][userAddress];
    Pool memory pool = pools[pId];
    uint256 accRewardPerShare = pool.accRewardPerShare;
    uint256 lpTokenBalance = IERC20(pool.lpToken).balanceOf(address(this));

    if(lpTokenBalance > 0 && pool.lastRewardBlock < block.timestamp){
      uint256 blockElapsed = _getMultiplier(pool.lastRewardBlock, block.timestamp);
      uint256 poolReward = (blockElapsed * sushiPerBlock * pool.allocPoints) / totalAllocPoints;
      accRewardPerShare += ((poolReward * CAL_MULTIPLIER) / lpTokenBalance);
    }

    uint earnedFromPoolInception = user.amount * accRewardPerShare / CAL_MULTIPLIER;
    return earnedFromPoolInception - user.rewardWriteOff;
  }

  function updatePools() public{
    uint256 length = pools.length;
    for(uint i; i < length; i++){
      updatePool(i);
    }
  }

  function deposit(uint256 pId, uint256 amount) external{
    require(amount > 0, "ZERO_AMOUNT");
    require(pools.length > pId, "INVALID_POOL");

    updatePool(pId);

    Pool memory pool = pools[pId];

    _claimSushiRewards(pId);

    User storage user = users[pId][msg.sender];
    user.amount += amount;
    user.rewardWriteOff =  user.amount * pool.accRewardPerShare / CAL_MULTIPLIER;

    IERC20(pool.lpToken).transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint256 pId, uint256 amount) external{
    require(amount > 0, "ZERO_AMOUNT");
    require(pools.length > pId, "INVALID_POOL");
    User storage user = users[pId][msg.sender];
    require(user.amount >= amount, "INVALID_AMOUNT");

    updatePool(pId);

    Pool memory pool = pools[pId];

    _claimSushiRewards(pId);

    user.amount -= amount;
    user.rewardWriteOff = user.amount * pool.accRewardPerShare / CAL_MULTIPLIER;

    IERC20(pool.lpToken).transfer(msg.sender, amount);
  }

  function _claimSushiRewards(uint256 pId) internal {
    User memory user = users[pId][msg.sender];
    if(user.amount == 0) return;
    Pool memory pool = pools[pId];

    uint256 earnedFromPoolInception = user.amount * pool.accRewardPerShare / CAL_MULTIPLIER;
    uint256 actualEarned = earnedFromPoolInception - user.rewardWriteOff;

    sushi.transfer(msg.sender , actualEarned);
  }

  function _getMultiplier(uint256 from, uint256 to) internal view returns (uint) {
    if(to <= bonusEndBlock){
      return (to - from) * BONUS_MULTIPLIER;
    } else if(from >= bonusEndBlock){
      return (to - from);
    } else {
      return ((bonusEndBlock - from ) * BONUS_MULTIPLIER) + (to - bonusEndBlock);
    }
  }

  // function _safeSushiTransfer(address receiver, uint amount) internal {
  //   if()
  // }
}