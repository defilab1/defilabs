// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "../interfaces/IOracle.sol";
import "../interfaces/IEIP20.sol";

library PolicyType {
    enum StakeType {Day1, Day7, Day30, Day60}
    enum BenefitType {T4, T5, T7}
}

interface IPool {
    function poolIncr() external view returns (uint256);
    function addPool(address token, uint256 _minAmount, uint256 _maxbenefit, PolicyType.BenefitType _benefitType) external;
    function setPool(uint256 _pid, PolicyType.StakeType _stakeType, uint256[] calldata _benefits) external;
}

contract PolicyP is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isDone = false;

    address public pool;

    address public cake;
    address public bnb;
    address public usdt;
    address public busd;
    address public btc;
    address public eth;

    uint256 public usdtDecimals;

    uint256 cake_min = 1;
    uint256 cake_maxbenefit = 0;
    uint256[] cake_day1  = [120,    130,    140,    150,    160,    170,    180];
    uint256[] cake_day7  = [125*7,  135*7,  145*7,  155*7,  165*7,  175*7,  185*7];
    uint256[] cake_day30 = [130*30, 140*30, 150*30, 160*30, 170*30, 180*30, 190*30];
    uint256[] cake_day60 = [135*60, 145*60, 155*60, 165*60, 175*60, 185*60, 195*60];

    uint256 bnb_min = 1;
    uint256 bnb_maxbenefit = 0;
    uint256[] bnb_day1   = [150,    154,    158,    162,    168,    174,    180];
    uint256[] bnb_day7   = [157*7,  161*7,  165*7,  169*7,  175*7,  181*7,  187*7];
    uint256[] bnb_day30  = [195*30, 199*30, 203*30, 207*30, 213*30, 219*30, 225*30];
    uint256[] bnb_day60  = [201*60, 205*60, 209*60, 213*60, 219*60, 225*60, 231*60];

    uint256 usdt_min = 1;
    uint256 usdt_maxbenefit = 0;
    uint256[] usdt_day1  = [185,    190,    195,    200,    210,    220,    230];
    uint256[] usdt_day7  = [191*7,  196*7,  201*7,  206*7,  216*7,  226*7,  236*7];
    uint256[] usdt_day30 = [210*30, 215*30, 220*30, 225*30, 235*30, 245*30, 255*30];
    uint256[] usdt_day60 = [240*60, 245*60, 250*60, 255*60, 265*60, 275*60, 285*60];

    uint256 busd_min = 1;
    uint256 busd_maxbenefit = 0;
    uint256[] busd_day1  = [160,    164,    168,    172,    178,    184,    190];
    uint256[] busd_day7  = [166*7,  170*7,  174*7,  178*7,  184*7,  190*7,  196*7];
    uint256[] busd_day30 = [210*30, 214*30, 218*30, 222*30, 228*30, 234*30, 240*30];
    uint256[] busd_day60 = [216*60, 220*60, 224*60, 228*60, 234*60, 240*60, 246*60];

    uint256 btc_min = 1;
    uint256 btc_maxbenefit = 0;
    uint256[] btc_day1   = [0,      0,      0,      80,     85,     90,     95];
    uint256[] btc_day7   = [0*7,    0*7,    0*7,    85*7,   90*7,   95*7,   100*7];
    uint256[] btc_day30  = [0*30,   0*30,   0*30,   90*30,  95*30,  100*30, 105*30];
    uint256[] btc_day60  = [0*60,   0*60,   0*60,   95*60,  100*60, 105*60, 110*60];

    uint256 eth_min = 1;
    uint256 eth_maxbenefit = 0;
    uint256[] eth_day1   = [0,      0,      100,    105,    110,    120,    130];
    uint256[] eth_day7   = [0*7,    0*7,    105*7,  110*7,  115*7,  125*7,  135*7];
    uint256[] eth_day30  = [0*30,   0*30,   110*30, 115*30, 120*30, 130*30, 140*30];
    uint256[] eth_day60  = [0*60,   0*60,   115*60, 120*60, 125*60, 135*60, 145*60];

    constructor(
        address _pool,
        address _cake,
        address _usdt,
        address _busd,
        address _btc,
        address _eth
    ) public {
        require(_pool != address(0), "pool zero");
        require(_cake != address(0), "cake zero");
        require(_usdt != address(0), "usdt zero");
        require(_busd != address(0), "busd zero");
        require(_btc != address(0), "btc zero");
        require(_eth != address(0), "eth zero");

        pool = _pool;
        usdtDecimals = 18;

        cake = _cake;
        bnb  = address(0);
        usdt = _usdt;
        busd = _busd;
        btc  = _btc;
        eth  = _eth;
    }

    function setPolicys() public onlyOwner {
        require(isDone == false, "Policy: is done");

        //cake
        IPool(pool).addPool(cake, cake_min * 10**usdtDecimals, cake_maxbenefit, PolicyType.BenefitType.T7);
        uint256 cake_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(cake_pid, PolicyType.StakeType.Day1,  cake_day1);
        IPool(pool).setPool(cake_pid, PolicyType.StakeType.Day7,  cake_day7);
        IPool(pool).setPool(cake_pid, PolicyType.StakeType.Day30, cake_day30);
        IPool(pool).setPool(cake_pid, PolicyType.StakeType.Day60, cake_day60);

        //bnb
        IPool(pool).addPool(bnb, bnb_min * 10**usdtDecimals, bnb_maxbenefit, PolicyType.BenefitType.T7);
        uint256 bnb_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(bnb_pid, PolicyType.StakeType.Day1,  bnb_day1);
        IPool(pool).setPool(bnb_pid, PolicyType.StakeType.Day7,  bnb_day7);
        IPool(pool).setPool(bnb_pid, PolicyType.StakeType.Day30, bnb_day30);
        IPool(pool).setPool(bnb_pid, PolicyType.StakeType.Day60, bnb_day60);

        //usdt
        IPool(pool).addPool(usdt, usdt_min * 10**usdtDecimals, usdt_maxbenefit, PolicyType.BenefitType.T7);
        uint256 usdt_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(usdt_pid, PolicyType.StakeType.Day1,  usdt_day1);
        IPool(pool).setPool(usdt_pid, PolicyType.StakeType.Day7,  usdt_day7);
        IPool(pool).setPool(usdt_pid, PolicyType.StakeType.Day30, usdt_day30);
        IPool(pool).setPool(usdt_pid, PolicyType.StakeType.Day60, usdt_day60);

        //busd
        IPool(pool).addPool(busd, busd_min * 10**usdtDecimals, busd_maxbenefit, PolicyType.BenefitType.T7);
        uint256 busd_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(busd_pid, PolicyType.StakeType.Day1,  busd_day1);
        IPool(pool).setPool(busd_pid, PolicyType.StakeType.Day7,  busd_day7);
        IPool(pool).setPool(busd_pid, PolicyType.StakeType.Day30, busd_day30);
        IPool(pool).setPool(busd_pid, PolicyType.StakeType.Day60, busd_day60);

        //btc
        IPool(pool).addPool(btc, btc_min * 10**usdtDecimals, btc_maxbenefit, PolicyType.BenefitType.T4);
        uint256 btc_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(btc_pid, PolicyType.StakeType.Day1,  btc_day1);
        IPool(pool).setPool(btc_pid, PolicyType.StakeType.Day7,  btc_day7);
        IPool(pool).setPool(btc_pid, PolicyType.StakeType.Day30, btc_day30);
        IPool(pool).setPool(btc_pid, PolicyType.StakeType.Day60, btc_day60);

        //eth
        IPool(pool).addPool(eth, eth_min * 10**usdtDecimals, eth_maxbenefit, PolicyType.BenefitType.T5);
        uint256 eth_pid = IPool(pool).poolIncr();
        IPool(pool).setPool(eth_pid, PolicyType.StakeType.Day1,  eth_day1);
        IPool(pool).setPool(eth_pid, PolicyType.StakeType.Day7,  eth_day7);
        IPool(pool).setPool(eth_pid, PolicyType.StakeType.Day30, eth_day30);
        IPool(pool).setPool(eth_pid, PolicyType.StakeType.Day60, eth_day60);

        isDone = true;
    }
}