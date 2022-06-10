pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ILiquidityGaugeV3.sol";
import "../interfaces/IIdleCDO.sol";
import "../interfaces/IStakeManager.sol";
import "../interfaces/IDistributorProxy.sol";

contract StakeStEthTranchesManager is IStakeManager , Ownable {
  using SafeERC20 for IERC20;

  mapping (address => bool) private rewardTokenExists;

  ILiquidityGaugeV3 private immutable gauge;
  IERC20 private immutable underlingToken;
  IERC20[] private rewardsTokens;
  IIdleCDO private immutable tranche;
  IDistributorProxy private constant distributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  constructor (address _gauge, address _underlingToken, address[] memory _rewardsTokens, address _tranche) {
    require(_gauge != address(0), "Gauge cannot be 0 address");
    require(_underlingToken != address(0), "UnderlingToken cannot be 0 address");
    require(_tranche != address(0), "Tranche cannot be 0 address");
    gauge = ILiquidityGaugeV3(_gauge);
    underlingToken = IERC20(_underlingToken);
    tranche = IIdleCDO(_tranche);
    _setRewardsTokens(_rewardsTokens);
  }

  function claimStaked() external onlyOwner {
    _claimStaked();
  }

  function _setRewardsTokens(address[] memory _rewardsToken) internal {
    for (uint256 index = 0; index < _rewardsToken.length; ++index) {
      require(rewardTokenExists[_rewardsToken[index]] == false, "Duplicate token");
      require(_rewardsToken[index] != address(0), "Reward Token cannot be 0 address");
      rewardTokenExists[_rewardsToken[index]] = true; 
      rewardsTokens.push(IERC20(_rewardsToken[index]));
    }
  }
  
  function _claimStaked() internal {
    uint256 balance = gauge.balanceOf(msg.sender);
    if (balance == 0) {
      return;
    }
    IERC20(address(gauge)).safeTransferFrom(msg.sender, address(this), balance);
    
    address sender = msg.sender;
    _claimIdle(sender);
    _withdrawAndClaimGauge();
    _withdrawTranchee();
    _transferRewardsTokens();
    _transferUnderlingToken(sender);
  }

  
  function _claimIdle(address _from) internal {
    distributorProxy.distribute_for(address(gauge), _from);
  }

  function _withdrawAndClaimGauge() internal {
    uint256 gaugeBalance  = gauge.balanceOf(address(this));
    gauge.withdraw(gaugeBalance, false);
  }

  function _withdrawTranchee() internal{
    address _trancheAA = tranche.AATranche();
    uint256 _trancheAABalance = IERC20(_trancheAA).balanceOf(address(this));
    tranche.withdrawAA(_trancheAABalance);
  }

  function _transferRewardsTokens() internal {
    IERC20[] memory _rewardsTokens = rewardsTokens;
    uint256 _rewardsTokenBalance;
    for (uint256 index = 0; index < _rewardsTokens.length; ++index) {
      _rewardsTokenBalance = _rewardsTokens[index].balanceOf(address(this));
      if (_rewardsTokenBalance > 0) {
        _rewardsTokens[index].safeTransfer(msg.sender, _rewardsTokenBalance);
      }
    }
  }

  function _transferUnderlingToken(address _to) internal {
    uint256 _underlingTokenBalance = underlingToken.balanceOf(address(this));
    underlingToken.safeTransfer(_to, _underlingTokenBalance);
  }

  function token() external view returns (address) {
    return address(underlingToken);
  }
  
  function stakedToken() external view returns (address){
    return address(gauge);
  }

}