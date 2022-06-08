// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.0 <=0.8.14;

interface ILiquidityGaugeV3 {
    function deposit(uint256 amount, address account, bool claimRewards) external;
    
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount, bool claimRewards) external;

    function claim_rewards(address account, address receiver) external;

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external;
    function approve(address _spender, uint256 value) external;
}
