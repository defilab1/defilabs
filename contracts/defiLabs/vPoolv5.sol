// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "../interfaces/IOracle.sol";
import "../interfaces/IEIP20.sol";

contract vPoolv5 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum StakeType {Day1, Day7, Day30, Day60}
    enum BenefitType {T4, T5, T7}

    // Info of each pool.
    struct PoolInfo {
        uint256 pid;
        address token;
        bool isOpen;
        BenefitType benefitType;
        uint256 totalSupply;
        uint256 minAmount;
        uint256 maxbenefit; //apr of day
        mapping(address => uint256) balances;
        mapping(address => mapping(StakeType => uint256)) balanceOfStakedType;
        mapping(StakeType => uint256[]) benefits; //0.01 = 100/10000
        uint256 createdAt;
    }

    struct StakeRecord {
        StakeType stakeType;
        address token;   //stake token
        address account;   //stake account
        uint256 amount;    //stake amount
        uint256 totalValue; //usdt value
        uint256 apy;   //0.01 = 100/10000
        uint256 lockDuration;  //1day, 7day or 30day
        uint256 createdAt;
    }

    struct UserInfo {
        uint256 deposit;
        uint256 reward;
        uint256 unLockedTime;
        uint256 lastUpdateTime;
        uint256 lockDuration;  //1day, 7day or 30day
        uint256 totalValue;
        uint256 apy;
    }

    uint256 public stakeRecordIncr = 0;
    mapping(uint256 => StakeRecord) public stakeRecords;

    mapping(uint256 => mapping(StakeType => mapping(address => UserInfo))) public userInfos;

    uint256 constant public denominator = 10000;

    uint256 constant public C_Day1 = 1 days;
    uint256 constant public C_Day7 = 7 days;
    uint256 constant public C_Day30 = 30 days;
    uint256 constant public C_Day60 = 60 days;

    uint256 constant public C_Day1_Number  = 1;
    uint256 constant public C_Day7_Number  = 7;
    uint256 constant public C_Day30_Number = 30;
    uint256 constant public C_Day60_Number = 60;

    uint256 public poolIncr = 0;
    mapping(uint256 => PoolInfo) public pools;

    address public oracle;
    address public funder;

    address public usdt;
    uint256 public usdtDecimals;
    uint256 public oneUsdt;

    uint256 constant public bonusFeeRate = 3000; //30% = 3000 / 10000

    uint256 private gSalt = 0;

    address public policyOperator; 

    constructor(
        address _oracle,
        address _usdt,
        address _funder
    ) public {
        require(_oracle != address(0), "oracle zero");
        require(_usdt != address(0), "usdt zero");
        require(_funder != address(0), "funder zero");

        oracle = _oracle;
        usdt = _usdt;
        funder = _funder;

        usdtDecimals = IEIP20(usdt).decimals();
        
        oneUsdt = 10**usdtDecimals;
    }

    function withdrawFunds(address _token, uint256 _amount) public payable nonReentrant {
        require(funder == msg.sender, "vPool: invalid recipient");

        if(address(_token) != address(0)) {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            safeTransferETH(msg.sender, _amount);
        }
    }

    function provideFunds(address _token, uint256 _amount) public payable nonReentrant {
        require(funder == msg.sender, "vPool: invalid recipient");

        uint256 amount = _amount;
        if(address(_token) == address(0)) {
            amount = msg.value;
        }

        if(address(_token) != address(0)) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }


    function getStakeMinimum(uint256 _pid) public view returns(uint256) {
        return pools[_pid].minAmount;
    }

    function getStakedType() public pure returns (StakeType, StakeType, StakeType, StakeType) {
        return (StakeType.Day1, StakeType.Day7, StakeType.Day30, StakeType.Day60);
    }

    function getStakeDays(StakeType _stakeType) public pure returns (uint256) {
        if (_stakeType == StakeType.Day1) {
            return C_Day1;
        } else if (_stakeType == StakeType.Day7) {
            return C_Day7;
        } else if (_stakeType == StakeType.Day30) {
            return C_Day30;
        } else {
            return C_Day60;
        }
    }

    function getBenefitIndex_7(uint256 amount_) public view returns (uint256) {
        if (amount_ >= oneUsdt.mul(20000)) {
            return 6;
        } else if (amount_ >= oneUsdt.mul(10000) && amount_ < oneUsdt.mul(20000)) {
            return 5;
        }  else if (amount_ >= oneUsdt.mul(5000) && amount_ < oneUsdt.mul(10000)) {
            return 4;
        } else if (amount_ >= oneUsdt.mul(3000) && amount_ < oneUsdt.mul(5000)) {
            return 3;
        } else if (amount_ >= oneUsdt.mul(1000) && amount_ < oneUsdt.mul(3000)) {
            return 2;
        } else if (amount_ >= oneUsdt.mul(500) && amount_ < oneUsdt.mul(1000)) {
            return 1;
        } else {
            return 0; //[1, 500)
        }
    }

    function getBenefitIndex_4(uint256 amount_) public view returns (uint256) {
        if (amount_ >= oneUsdt.mul(20000)) {
            return 6;
        } else if (amount_ >= oneUsdt.mul(10000) && amount_ < oneUsdt.mul(20000)) {
            return 5;
        }  else if (amount_ >= oneUsdt.mul(5000) && amount_ < oneUsdt.mul(10000)) {
            return 4;
        } else {
            return 3; //[1, 4999)
        }
    }

    function getBenefitIndex_5(uint256 amount_) public view returns (uint256) {
        if (amount_ >= oneUsdt.mul(20000)) {
            return 6;
        } else if (amount_ >= oneUsdt.mul(10000) && amount_ < oneUsdt.mul(20000)) {
            return 5;
        }  else if (amount_ >= oneUsdt.mul(5000) && amount_ < oneUsdt.mul(10000)) {
            return 4;
        } else if (amount_ >= oneUsdt.mul(3000) && amount_ < oneUsdt.mul(5000)) {
            return 3;
        }  else {
            return 2; //[1, 2999)
        }
    }

    function getBenefitIndex(BenefitType benefitType_, uint256 amount_) public view returns (uint256) {
        if (benefitType_ == BenefitType.T4) {
            return getBenefitIndex_4(amount_);
        } else if (benefitType_ == BenefitType.T5) {
            return getBenefitIndex_5(amount_);
        } else {
            return getBenefitIndex_7(amount_);
        }
    }

    modifier onlyOperator() {
        require(msg.sender == policyOperator, "vPool: invalid policy operator");
        
        _;
    }

    function updateOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "operator zero");
        policyOperator = _operator;
    }

    function updateOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "new oracle zero");
        oracle = _newOracle;
    }

    function updateFunder(address _funder) external onlyOwner {
        require(_funder != address(0), "funder zero");
        funder = _funder;
    }

    function addPool(address token, uint256 _minAmount, uint256 _maxbenefit, BenefitType _benefitType) external onlyOperator {
        poolIncr = poolIncr.add(1);
        
        PoolInfo memory info = PoolInfo({
            pid: poolIncr,
            token: token,
            isOpen: true,
            benefitType: _benefitType,
            totalSupply: 0,
            minAmount: _minAmount,
            maxbenefit: _maxbenefit,
            createdAt: block.timestamp
        });
        pools[poolIncr] = info;
    }

    function setPool(uint256 _pid, StakeType _stakeType, uint256[] calldata _benefits) external onlyOperator {
        require(_pid != 0, "vPool: invalid pid");
        require(_benefits.length == 7, "vPool: invalid benefits length");

        PoolInfo storage poolInfo = pools[_pid];
        require(poolInfo.pid != 0, "vPool: invalid pool");
        require(poolInfo.benefits[_stakeType].length == 0, "vPool: benefits has set");

        for(uint i = 0; i < _benefits.length; i++) {
            poolInfo.benefits[_stakeType].push(_benefits[i]);
        }
    }

    function getPoolInfo(uint256 _pid) public view returns(address, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory) {
        return (
            pools[_pid].token,
            pools[_pid].benefits[StakeType.Day1],
            pools[_pid].benefits[StakeType.Day7],
            pools[_pid].benefits[StakeType.Day30],
            pools[_pid].benefits[StakeType.Day60]
        );
    }

    function balanceOf(uint256 _pid, address _account) public view returns(uint256) {
        return pools[_pid].balances[_account];
    }

    function getBalanceOfStakedType(uint256 _pid, address _account, StakeType _stakeType) public view returns(uint256) {
        return pools[_pid].balanceOfStakedType[_account][_stakeType];
    }

    function totalSupply(uint256 _pid) public view returns(uint256) {
        return pools[_pid].totalSupply;
    }

    function getUserInfo(uint256 _pid, StakeType _stakeType, address _account) public view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        UserInfo memory userInfo = userInfos[_pid][_stakeType][_account];
        return (
            userInfo.deposit,
            userInfo.reward,
            userInfo.unLockedTime,
            userInfo.lastUpdateTime,
            userInfo.lockDuration,
            userInfo.totalValue,
            userInfo.apy
        );
    }

    function getRecordInfo(uint256 _recordId) public view returns (StakeType, address, address, uint256, uint256, uint256, uint256, uint256) {
        StakeRecord memory record = stakeRecords[_recordId];
        return (
            record.stakeType,
            record.token,
            record.account,
            record.amount,
            record.totalValue,
            record.apy,
            record.lockDuration,
            record.createdAt);
    }

    function earned(uint256 _pid, StakeType _stakeType, address _account) public view returns(uint256) {
        UserInfo memory userInfo = userInfos[_pid][_stakeType][_account];
        uint256 bonus = calcBonus(_pid, _stakeType, _account);
        return userInfo.reward.add(bonus);
    }

    function calcBonus(uint256 _pid, StakeType _stakeType, address _account) public view returns(uint256) {
        UserInfo memory userInfo = userInfos[_pid][_stakeType][_account];
        uint256 lockDuration = userInfo.lockDuration;
        if (lockDuration == 0) {
            return 0;
        }

        uint256 lastUpdateTime = userInfo.lastUpdateTime;
        uint256 unLockedTime = userInfo.unLockedTime;
        uint256 apy = userInfo.apy;
        uint256 totalBonus = userInfo.totalValue.mul(apy).div(denominator);
        uint256 bonusRate = totalBonus.mul(denominator).div(lockDuration);

        if (block.timestamp > unLockedTime) {
            return bonusRate.mul(unLockedTime - lastUpdateTime).div(denominator);
        } else {
            return bonusRate.mul(block.timestamp - lastUpdateTime).div(denominator);
        }
    }

    function calcBenefit(uint256 _benefit, uint256 _random) internal pure returns(uint256) {
        // r*0.9 + RAND()*r*19%
        uint256 a = _benefit.mul(9).div(10).mul(denominator);
        uint256 b = _benefit.mul(19).div(100);
        uint256 c = b.mul(_random).mul(denominator);
        return (a + c).div(denominator);
    }

    //random: [0, 10000]
    function doRand() internal returns(uint256) {
        uint256 h = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, gSalt)));
        uint256 random = h % denominator;
        gSalt = gSalt.add(1);
        return random;
    }

    function calcMaxbenefit(StakeType _stakeType, uint256 _maxbenefit) public pure returns(uint256) {
        if (_stakeType == StakeType.Day1) {
            return C_Day1_Number.mul(_maxbenefit);
        } else if (_stakeType == StakeType.Day7) {
            return C_Day7_Number.mul(_maxbenefit);
        } else if (_stakeType == StakeType.Day30) {
            return C_Day30_Number.mul(_maxbenefit);
        } else {
            return C_Day60_Number.mul(_maxbenefit);
        }
    }

    function deposit(uint256 _pid, StakeType _stakeType, uint256 _amount) public payable nonReentrant {
        require(_pid != 0, "vPool: invalid pid");

        PoolInfo storage poolInfo = pools[_pid];
        require(poolInfo.pid != 0, "vPool: invalid pool");
        require(poolInfo.isOpen == true, "vPool: pool is not opened");

        address token = poolInfo.token;
        uint256 amount = _amount;
        if (token == address(0)) {
            amount = msg.value;
        }
        require(amount > 0, 'vPool: cannot stake 0');

        uint256 totalValue = IOracle(oracle).consult(token, amount);
        require(totalValue >= poolInfo.minAmount, "vPool: stake amount must > min");

        //find index
        uint256 benefit = poolInfo.benefits[_stakeType][getBenefitIndex(poolInfo.benefitType, totalValue)];
        require(benefit > 0, "vPool: benefit must > 0");
        uint256 lockDuration = getStakeDays(_stakeType);

        uint256 random = doRand();
        uint256 randBenefit = calcBenefit(benefit, random);
        if (poolInfo.maxbenefit > 0) {
            randBenefit = Math.min(randBenefit, calcMaxbenefit(_stakeType, poolInfo.maxbenefit));
        }

        UserInfo storage userInfo = userInfos[_pid][_stakeType][msg.sender];

        //Collect the obtained rewards
        uint256 bonus = calcBonus(_pid, _stakeType, msg.sender);
        userInfo.reward = userInfo.reward.add(bonus);

        //reset apy
        if (userInfo.deposit == 0) {
            userInfo.apy = randBenefit;
        }

        userInfo.totalValue = userInfo.totalValue.add(totalValue);
        userInfo.deposit = userInfo.deposit.add(amount);

        userInfo.lastUpdateTime = block.timestamp;
        userInfo.unLockedTime = block.timestamp.add(lockDuration);
        userInfo.lockDuration = lockDuration;

        poolInfo.balances[msg.sender] = poolInfo.balances[msg.sender].add(amount);
        poolInfo.balanceOfStakedType[msg.sender][_stakeType] = poolInfo.balanceOfStakedType[msg.sender][_stakeType].add(amount);
        poolInfo.totalSupply = poolInfo.totalSupply.add(amount);

        //new record
        uint256 apy = userInfo.apy;
        StakeRecord memory record = StakeRecord({
            stakeType: _stakeType, 
            token: token,
            account: msg.sender,
            amount: amount,
            totalValue: totalValue,
            apy: apy,
            lockDuration: lockDuration,
            createdAt: block.timestamp
        });
        stakeRecordIncr = stakeRecordIncr.add(1);
        stakeRecords[stakeRecordIncr] = record;

        //transfer token to a recipient
        // if(address(token) != address(0)) {
        //     IERC20(token).safeTransferFrom(msg.sender, tokenRecipient, amount);
        // } else {
        //     safeTransferETH(tokenRecipient, amount);
        // }

        if (address(token) != address(0)) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function reStake(uint256 _pid, StakeType _stakeType) public nonReentrant {
        require(_pid != 0, "vPool: invalid pid");

        PoolInfo storage poolInfo = pools[_pid];
        require(poolInfo.isOpen == true, "vPool: pool is not opened");

        UserInfo storage userInfo = userInfos[_pid][_stakeType][msg.sender];
        require(userInfo.unLockedTime <= block.timestamp, "vPool: stake is locked");

        //Collect the obtained rewards
        uint256 lastBonus = calcBonus(_pid, _stakeType, msg.sender);
        userInfo.reward = userInfo.reward.add(lastBonus);

        //restake
        uint256 lockDuration = userInfo.lockDuration;
        userInfo.lastUpdateTime = block.timestamp;
        userInfo.unLockedTime = block.timestamp.add(lockDuration);

        //new record
        address token = poolInfo.token;
        uint256 amount = userInfo.deposit;
        uint256 totalValue = userInfo.totalValue;
        uint256 apy = userInfo.apy;
        StakeRecord memory record = StakeRecord({
            stakeType: _stakeType, 
            token: token,
            account: msg.sender,
            amount: amount,
            totalValue: totalValue,
            apy: apy,
            lockDuration: lockDuration,
            createdAt: block.timestamp
        });
        stakeRecordIncr = stakeRecordIncr.add(1);
        stakeRecords[stakeRecordIncr] = record;
    }

    function exit(uint256 _pid, StakeType _stakeType) public nonReentrant {
        require(_pid != 0, "vPool: invalid pid");

        PoolInfo storage poolInfo = pools[_pid];
        require(poolInfo.isOpen == true, "vPool: pool is not opened");

        UserInfo storage userInfo = userInfos[_pid][_stakeType][msg.sender];
        require(userInfo.unLockedTime <= block.timestamp, "vPool: stake is locked");

        //Collect the obtained rewards
        uint256 lastBonus = calcBonus(_pid, _stakeType, msg.sender);
        userInfo.reward = userInfo.reward.add(lastBonus);

        uint256 bonus = userInfo.reward;
        uint256 fee = bonus.mul(bonusFeeRate).div(denominator);
        uint256 actualBonus = bonus.sub(fee);
        
        uint256 amount = userInfo.deposit;

        userInfo.lastUpdateTime = userInfo.unLockedTime;
        userInfo.deposit = 0;
        userInfo.totalValue = 0;
        userInfo.reward = 0;
        userInfo.apy = 0;

        poolInfo.balances[msg.sender] = poolInfo.balances[msg.sender].sub(amount);
        poolInfo.balanceOfStakedType[msg.sender][_stakeType] = poolInfo.balanceOfStakedType[msg.sender][_stakeType].sub(amount);
        poolInfo.totalSupply = poolInfo.totalSupply.sub(amount);

        address token = poolInfo.token;
        
        // bonus
        IERC20(usdt).safeTransfer(msg.sender, actualBonus);

        // principal
        if(address(token) != address(0)) {
            IERC20(token).safeTransfer(msg.sender, amount);
        } else {
            safeTransferETH(msg.sender, amount);
        }
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    receive() external payable {}
}