// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IOracle {
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut);
}
