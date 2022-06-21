pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StakeManagerTranches.sol";

import "../interfaces/IStakeManager.sol";
import "../interfaces/ICrvPool.sol";

contract StakeCrvTranchesManager is IStakeManager, Ownable, StakeManagerTranches {

  struct TokenInterfaces {
    IERC20 CrvLPToken;
    ICrvPool CrvPool;
  }

  mapping (address => TokenInterfaces) private tokenInterfaces;

  constructor (address[] memory _gauges, address[][] memory _underlyingToken, address[] memory _tranches, address[] memory _crvPools, address[] memory _crvLPTokens) StakeManagerTranches(_gauges, _underlyingToken, _tranches) {
    for (uint256 index = 0; index < _gauges.length; index++) {
      tokenInterfaces[_gauges[index]] = TokenInterfaces(IERC20(_crvPools[index]), ICrvPool(_crvLPTokens[index]));
    }
  }

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
    
    address _stakedToken;
    for (uint256 index = 0; index < _stakeTokens.length; index++) {
      _stakedToken = _stakeTokens[index]._address;
      uint256 balance = _gaugeBalance(_stakedToken, sender);
      if (balance == 0) {continue;}

      (uint256[2] memory _minAmounts) = abi.decode(_stakeTokens[index]._extraData, (uint256[2]));

      _claimIdle(_stakedToken, sender);
      _claimRewards(_stakedToken, sender);
      _withdrawAndClaimGauge(_stakedToken, sender);
      _withdrawTranchee(_stakedToken);
      _removeLiquidity(_stakedToken, _minAmounts);
      _transferUnderlyingToken(_stakedToken, sender);
    }
  }

  function _removeLiquidity(address _stakeToken, uint256[2] memory _minAmounts) internal {
    TokenInterfaces memory _tokenInterfaces = tokenInterfaces[_stakeToken];
    uint256 _balanceCRVToken = _tokenInterfaces.CrvLPToken.balanceOf(address(this));
    _tokenInterfaces.CrvPool.remove_liquidity(_balanceCRVToken, _minAmounts);
  }

  function stakedTokens() view external override returns(address[] memory) {
    return _stakedTokens();
  }

}