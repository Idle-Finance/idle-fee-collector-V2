pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StakeManagerTranches.sol";

import "../interfaces/IStakeManager.sol";

contract StakeStEthTranchesManager is IStakeManager, Ownable, StakeManagerTranches {
  using SafeERC20 for IERC20;

  
  constructor (address[] memory _gauges, address[][] memory _underlyingToken, address[] memory _tranches) StakeManagerTranches(_gauges, _underlyingToken, _tranches) {}

  function claimStaked(StakeToken[] calldata _stakeTokens) external onlyOwner {
    _claimStaked(_stakeTokens);
  }

  function withdrawAdmin(address _stakeToken, address _toAddress, uint256[] calldata _amounts) external override onlyOwner {
    _withdrawAdmin(_stakeToken, _toAddress, _amounts);
  }

  function addStakedToken(address _gauge, address _tranche, address[] calldata _underlyingTokens) external override onlyOwner {
    _addStakedToken(_gauge, _tranche, _underlyingTokens);
  }

  function removeStakedToken(uint256 _index) external override onlyOwner {
    _removeStakedToken(_index);
  }
  
  function _claimStaked(StakeToken[] calldata _stakeTokens) internal {
    address sender = msg.sender;
    
    address _stakedToken ;
    for (uint256 index = 0; index < _stakeTokens.length; index++) {
      _stakedToken =_stakeTokens[index]._address;

      uint256 balance = _gaugeBalance(_stakedToken, sender);
      if (balance == 0) {continue;}

      _claimRewards(_stakedToken, sender);
      _claimIdle(_stakedToken, sender);
      _withdrawAndClaimGauge(_stakedToken, sender);
      _withdrawTranchee(_stakedToken);
      _transferUnderlyingToken(_stakedToken, sender);
    }
  }

  function stakedTokens() view external returns(address[] memory) {
    return _stakedTokens();
  }

}