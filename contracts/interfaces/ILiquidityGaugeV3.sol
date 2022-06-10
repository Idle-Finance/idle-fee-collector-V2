// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.0 <=0.8.14;

interface ILiquidityGaugeV3 {
    function deposit(uint256 amount, address account, bool claimRewards) external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount, bool claimRewards) external;
    function set_rewards_receiver(address account) external;
    function integrate_checkpoint() external;
    function user_checkpoint(address account) external;
    function claim_rewards() external;
    function claim_rewards(address account, address receiver) external;
    function claimable_reward(address account, address token) external view returns(uint256);
    function integrate_fraction(address account) external view returns(uint256);
    function claimable_reward_write(address account, address token) external view returns(uint256);
    function rewards_receiver(address account) external view returns(address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external;
    function approve(address _spender, uint256 value) external;
    function set_rewards(address _reward_contract, bytes32 _sigs, address[8] calldata _reward_tokens) external;
}
