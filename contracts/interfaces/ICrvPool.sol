
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <=0.8.14;

interface ICrvPool {
    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts) external ;
}