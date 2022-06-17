pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IDistributorProxy.sol";
import "./StakeManagerTranches.sol";
import "../interfaces/ILiquidityGaugeV3.sol";
import "../interfaces/IIdleCDO.sol";
import "../interfaces/IStakeManager.sol";

contract StakeManagerTranches  {
  using SafeERC20 for IERC20;

  mapping (address => bool) private underlyingTokenExists;

  ILiquidityGaugeV3 private immutable Gauge;
  IIdleCDO private immutable Tranche;
  IERC20[] private UnderlyingTokens;
  IDistributorProxy private constant DistributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  constructor (address _gauge, address[] memory _underlyingToken, address _tranche) {
    require(_gauge != address(0), "Gauge cannot be 0 address");
    require(_tranche != address(0), "Tranche cannot be 0 address");
    Gauge = ILiquidityGaugeV3(_gauge);
    Tranche = IIdleCDO(_tranche);
    _setUnderlyingTokens(_underlyingToken);
  }

  function _setUnderlyingTokens(address[] memory _token) internal {
    for (uint256 index = 0; index < _token.length; ++index) {
      require(underlyingTokenExists[_token[index]] == false, "Duplicate token");
      require(_token[index] != address(0), "Underlying token cannot be 0 address");
      underlyingTokenExists[_token[index]] = true; 
      UnderlyingTokens.push(IERC20(_token[index]));
    }
  }

  function _claimIdle(address _from) internal {
    DistributorProxy.distribute_for(address(Gauge), _from);
  }

  function _claimRewards(address _from) internal {
    Gauge.claim_rewards(_from);
  }

  function _withdrawAndClaimGauge(address _from) internal {
    uint256 balance = _gaugeBalance(_from);
    IERC20(address(Gauge)).safeTransferFrom(_from, address(this), balance);
    Gauge.withdraw(balance, false);
  }

  function _withdrawTranchee() internal{
    address _trancheAA = Tranche.AATranche();
    uint256 _trancheAABalance = IERC20(_trancheAA).balanceOf(address(this));
    Tranche.withdrawAA(_trancheAABalance);
  }

  function _transferUnderlyingToken(address _to) internal {
    IERC20[] memory _underlyingTokens = UnderlyingTokens;
    uint256 _underlyingTokenBalance;
    for (uint256 index = 0; index < _underlyingTokens.length; ++index) {
      _underlyingTokenBalance = _underlyingTokens[index].balanceOf(address(this));
      _underlyingTokens[index].safeTransfer(_to, _underlyingTokenBalance);
    }
  }

  function _withdrawAdmin(address _toAddress, uint256[] calldata _amounts) internal {
    require(_amounts.length == UnderlyingTokens.length, "Invalid length");
    for (uint256 index = 0; index < UnderlyingTokens.length; ++index) {
      if(_amounts[index] == 0) {continue;}
      UnderlyingTokens[index].safeTransfer(_toAddress, _amounts[index]);
    }
  }

  function _gaugeBalance(address _for) internal returns(uint256 balance){
    balance = Gauge.balanceOf(_for);
  }


  function _tokens() internal view returns (IERC20[] memory) {
    return UnderlyingTokens;
  }
  
  function _stakedToken() internal view returns (address){
    return address(Gauge);
  }

}