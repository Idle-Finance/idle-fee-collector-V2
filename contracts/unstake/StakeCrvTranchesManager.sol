pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ILiquidityGaugeV3.sol";
import "../interfaces/IIdleCDO.sol";
import "../interfaces/IStakeManager.sol";
import "../interfaces/IDistributorProxy.sol";
import "../interfaces/ICrvPool.sol";

contract StakeCrvTranchesManager is IStakeManager, Ownable {
  using SafeERC20 for IERC20;

  mapping (address => bool) private underlyingTokenExists;

  ILiquidityGaugeV3 private immutable Gauge;
  IERC20 private immutable CrvLPToken;
  ICrvPool private immutable CrvPool;
  IERC20[] private UnderlyingTokens;
  IIdleCDO private immutable Tranche;
  IDistributorProxy private constant DistributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  constructor (address _gauge, address[] memory _underlyingToken, address _tranche, address _crvPool, address _crvLPToken) {
    require(_gauge != address(0), "Gauge cannot be 0 address");
    require(_tranche != address(0), "Tranche cannot be 0 address");
    Gauge = ILiquidityGaugeV3(_gauge);
    Tranche = IIdleCDO(_tranche);
    CrvPool = ICrvPool(_crvPool);
    CrvLPToken = IERC20(_crvLPToken);
    _setUnderlyingTokens(_underlyingToken);
  }

  function claimStaked() external onlyOwner {
    _claimStaked();
  }

  function _setUnderlyingTokens(address[] memory _token) internal {
    for (uint256 index = 0; index < _token.length; ++index) {
      require(underlyingTokenExists[_token[index]] == false, "Duplicate token");
      require(_token[index] != address(0), "Underlying token cannot be 0 address");
      underlyingTokenExists[_token[index]] = true; 
      UnderlyingTokens.push(IERC20(_token[index]));
    }
  }
  
  function _claimStaked() internal {
    uint256 balance = Gauge.balanceOf(msg.sender);
    if (balance == 0) {
      return;
    }
    IERC20(address(Gauge)).safeTransferFrom(msg.sender, address(this), balance);
    
    address sender = msg.sender;
    _claimIdle(sender);
    _withdrawAndClaimGauge();
    _withdrawTranchee();
    _removeLiquidity();
    _transferUnderlyingToken(sender);
  }

  
  function _claimIdle(address _from) internal {
    DistributorProxy.distribute_for(address(Gauge), _from);
  }

  function _withdrawAndClaimGauge() internal {
    uint256 gaugeBalance  = Gauge.balanceOf(address(this));
    Gauge.withdraw(gaugeBalance, false);
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

  function _removeLiquidity() internal {
    uint256 _balanceCRVToken = CrvLPToken.balanceOf(address(this));
    uint256[2] memory _minAmounts;
    _minAmounts[0] = 0;
    _minAmounts[1] = 0;
    CrvPool.remove_liquidity(_balanceCRVToken, _minAmounts);
  }

  function token() external view returns (IERC20[] memory) {
    return UnderlyingTokens;
  }
  
  function stakedToken() external view returns (address){
    return address(Gauge);
  }

}