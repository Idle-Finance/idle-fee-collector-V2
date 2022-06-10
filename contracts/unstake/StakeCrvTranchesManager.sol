pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ILiquidityGaugeV3.sol";
import "../interfaces/IIdleCDO.sol";
import "../interfaces/IStakeManager.sol";
import "../interfaces/IDistributorProxy.sol";
import "../interfaces/ICrvPool.sol";

contract StakeCrvTranchesManager is IStakeManager , Ownable {
  using SafeERC20 for IERC20;

  mapping (address => bool) private underlingTokenExists;

  ILiquidityGaugeV3 private immutable gauge;
  IERC20 private immutable crvLPToken;
  ICrvPool private immutable crvPool;
  IERC20[] private underlingTokens;
  IERC20 private immutable rewardsToken;
  IIdleCDO private immutable tranche;
  IDistributorProxy private constant distributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  constructor (address _gauge, address[] memory _underlingToken, address _rewardsToken, address _tranche, address _crvPool, address _crvLPToken) {
    require(_gauge != address(0), "Gauge cannot be 0 address");
    require(_rewardsToken != address(0), "Rewards Token cannot be 0 address");
    require(_tranche != address(0), "Tranche cannot be 0 address");
    gauge = ILiquidityGaugeV3(_gauge);
    tranche = IIdleCDO(_tranche);
    rewardsToken = IERC20(_rewardsToken);
    crvPool = ICrvPool(_crvPool);
    crvLPToken = IERC20(_crvLPToken);
    _setUnderlingTokens(_underlingToken);
  }

  function claimStaked() external onlyOwner {
    _claimStaked();
  }

  function _setUnderlingTokens(address[] memory _token) internal {
    for (uint256 index = 0; index < _token.length; ++index) {
      require(underlingTokenExists[_token[index]] == false, "Duplicate token");
      require(_token[index] != address(0), "Underling token cannot be 0 address");
      underlingTokenExists[_token[index]] = true; 
      underlingTokens.push(IERC20(_token[index]));
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
    _removeLiquidity();
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
    uint256 _rewardsTokenBalance = rewardsToken.balanceOf(address(this));
    rewardsToken.safeTransfer(msg.sender, _rewardsTokenBalance);
  }

  function _transferUnderlingToken(address _to) internal {
    IERC20[] memory _underlingTokens = underlingTokens;
    uint256 _underlingTokenBalance;
    for (uint256 index = 0; index < _underlingTokens.length; ++index) {
      _underlingTokenBalance = _underlingTokens[index].balanceOf(address(this));
      _underlingTokens[index].safeTransfer(_to, _underlingTokenBalance);
      
    }
  }

  function _removeLiquidity() internal {
    uint256 _balanceCRVToken = crvLPToken.balanceOf(address(this));
    uint256[2] memory _minAmounts;
    _minAmounts[0] = 0;
    _minAmounts[1] = 0;
    crvPool.remove_liquidity(_balanceCRVToken, _minAmounts);
  }

  function token() external view returns (IERC20[] memory) {
    return underlingTokens;
  }
  
  function stakedToken() external view returns (address){
    return address(gauge);
  }

}