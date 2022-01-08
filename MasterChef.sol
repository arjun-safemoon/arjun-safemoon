// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

// MasterChef is the master of Cosmi. He can make Cosmi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once COSMI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of COSMIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCosmiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCosmiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. COSMIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that COSMIs distribution occurs.
        uint256 accCosmiPerShare; // Accumulated COSMIs per share, times 1e12. See below.
    }
    // The COSMI TOKEN!
    address public cosmi;
    // COSMI tokens created per block.
    uint256 public cosmiPerBlock;
    // Bonus muliplier for early cosmi makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Pool lptokens info
    mapping (IERC20 => bool) public lpTokensStatus;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when COSMI mining starts.
    uint256 public startBlock;
    // This mapping will store block.timestamp at the time of deposit for a specific user
    mapping(address => uint256) timeAtDeposit;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _cosmi,
        uint256 _cosmiPerBlock,
        uint256 _startBlock
    ) public {
        cosmi = _cosmi;
        cosmiPerBlock = _cosmiPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        require(lpTokensStatus[_lpToken] != true, "Cosmipay Token token already added");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accCosmiPerShare: 0
            })
        );
        lpTokensStatus[_lpToken] = true;
    }

    // Update the given pool's COSMI allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending COSMIs on frontend.
    function pendingCosmi(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCosmiPerShare = pool.accCosmiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cosmiReward =
                multiplier.mul(cosmiPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accCosmiPerShare = accCosmiPerShare.add(
                cosmiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accCosmiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 cosmiReward =
            multiplier.mul(cosmiPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        pool.accCosmiPerShare = pool.accCosmiPerShare.add(
            cosmiReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for COSMI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        timeAtDeposit[msg.sender] = block.timestamp;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accCosmiPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeCosmiTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accCosmiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(block.timestamp >= timeAtDeposit[msg.sender] + 1814400, "!! Withdraw available after 21 days from deposit !!");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accCosmiPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safeCosmiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accCosmiPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Safe cosmi transfer function, just in case if rounding error causes pool to not have enough COSMIs.
    function safeCosmiTransfer(address _to, uint256 _amount) internal {
        uint256 cosmiBal = IERC20(cosmi).balanceOf(address(this));
        if (_amount > cosmiBal) {
            IERC20(cosmi).transfer(_to, cosmiBal);
        } else {
            IERC20(cosmi).transfer(_to, _amount);
        }
    }

    function userStakingAmount(address _user) external view returns(uint256) {
        UserInfo storage user = userInfo[0][_user];
        return user.amount;
    }

}
