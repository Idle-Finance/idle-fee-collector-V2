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


  struct TokenBaseInterfaces {
    ILiquidityGaugeV3 gauge;
    IIdleCDO tranche;
    IERC20[] underlyingTokens;
  }

  mapping (address => TokenBaseInterfaces) private tokenBaseInterfaces;
  address[] private gaugeTokens;

  IDistributorProxy private constant DistributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  constructor (address[] memory _gauges, address[][] memory _underlyingTokens, address[] memory _tranches) {
    for (uint256 index = 0; index < _gauges.length; index++) {
      IERC20[] memory _tokens = new IERC20[](_underlyingTokens[index].length);
      for (uint256 x = 0; x < _underlyingTokens[index].length; x++) {
        _tokens[x] = IERC20(_underlyingTokens[index][x]);  
      }
      tokenBaseInterfaces[_gauges[index]] = TokenBaseInterfaces(ILiquidityGaugeV3(_gauges[index]), IIdleCDO(_tranches[index]), _tokens);
      gaugeTokens.push(_gauges[index]);
    }

  }

  function _claimIdle(address _stakeToken, address _from) internal {
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    DistributorProxy.distribute_for(address(_tokenInterfaces.gauge), _from);
  }

  function _claimRewards(address _stakeToken, address _from) internal {
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    _tokenInterfaces.gauge.claim_rewards(_from);
  }

  function _withdrawAndClaimGauge(address _stakeToken, address _from) internal {
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    uint256 balance = _gaugeBalance(_stakeToken, _from);
    IERC20(address(_tokenInterfaces.gauge)).safeTransferFrom(_from, address(this), balance);
    _tokenInterfaces.gauge.withdraw(balance, false);
  }

  function _withdrawTranchee(address _stakeToken) internal{
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    address _trancheAA = _tokenInterfaces.tranche.AATranche();
    uint256 _trancheAABalance = IERC20(_trancheAA).balanceOf(address(this));
     _tokenInterfaces.tranche.withdrawAA(_trancheAABalance);
  }

  function _transferUnderlyingToken(address _stakeToken, address _to) internal {
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    IERC20[] memory _underlyingTokens = _tokenInterfaces.underlyingTokens;
    uint256 _underlyingTokenBalance;
    for (uint256 index = 0; index < _underlyingTokens.length; ++index) {
      _underlyingTokenBalance = _underlyingTokens[index].balanceOf(address(this));
      _underlyingTokens[index].safeTransfer(_to, _underlyingTokenBalance);
    }
  }

  function _withdrawAdmin(address _stakeToken, address _toAddress, uint256[] calldata _amounts) internal {
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    IERC20[] memory _underlyingTokens = _tokenInterfaces.underlyingTokens;
    require(_amounts.length == _underlyingTokens.length, "Invalid length");
    for (uint256 index = 0; index < _underlyingTokens.length; ++index) {
      if(_amounts[index] == 0) {continue;}
      _underlyingTokens[index].safeTransfer(_toAddress, _amounts[index]);
    }
  }

  function _addStakedToken(address _gauge, address _tranche, address[] calldata _underlyingTokens) internal {
    require(address(tokenBaseInterfaces[_gauge].gauge) == address(0), "Stake token already exists");
    IERC20[] memory _tokens = new IERC20[](_underlyingTokens.length);
    for (uint256 index = 0; index < _underlyingTokens.length; index++) {
      _tokens[index] = IERC20(_underlyingTokens[index]);  
    }
    tokenBaseInterfaces[_gauge] = TokenBaseInterfaces(ILiquidityGaugeV3(_gauge), IIdleCDO(_tranche), _tokens);
    gaugeTokens.push(_gauge);
  }

  function _removeStakedToken(uint256 _index) internal {
    delete tokenBaseInterfaces[gaugeTokens[_index]];
    gaugeTokens[_index] = gaugeTokens[gaugeTokens.length-1];
    gaugeTokens.pop();
  }

  function _gaugeBalance(address _stakeToken, address _for) internal returns(uint256 balance){
    TokenBaseInterfaces memory _tokenInterfaces = tokenBaseInterfaces[_stakeToken];
    balance = _tokenInterfaces.gauge.balanceOf(_for);
  }

  function _stakedTokens() internal view returns(address[] memory) {
    return gaugeTokens;
  }
}