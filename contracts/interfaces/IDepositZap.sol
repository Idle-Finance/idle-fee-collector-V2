
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <=0.8.14;


interface IDepositZap {
    function add_liquidity(address _pool, uint256[4] memory _deposit_amounts, uint256 _min_mint_amount) external returns (uint256);
}