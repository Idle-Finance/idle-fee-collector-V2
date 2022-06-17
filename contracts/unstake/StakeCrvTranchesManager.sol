pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StakeManagerTranches.sol";

import "../interfaces/IStakeManager.sol";
import "../interfaces/ICrvPool.sol";

contract StakeCrvTranchesManager is IStakeManager, Ownable, StakeManagerTranches {

  IERC20 private immutable CrvLPToken;
  ICrvPool private immutable CrvPool;
  

  constructor (address _gauge, address[] memory _underlyingToken, address _tranche, address _crvPool, address _crvLPToken) StakeManagerTranches(_gauge, _underlyingToken, _tranche) {
    CrvPool = ICrvPool(_crvPool);
    CrvLPToken = IERC20(_crvLPToken);
  }

  function claimStaked(bytes calldata _extraDatas) external onlyOwner {
    _claimStaked(_extraDatas);
  }

  function withdrawAdmin(address _toAddress, uint256[] calldata _amounts) external override onlyOwner {
    _withdrawAdmin(_toAddress, _amounts);
  }
  
  function _claimStaked(bytes calldata _extraDatas) internal {
    address sender = msg.sender;
    uint256 balance = _gaugeBalance(sender);
    if (balance == 0) {
      return;
    }
    (uint256[2] memory _minAmounts) = abi.decode(_extraDatas, (uint256[2]));

    _claimIdle(sender);
    _withdrawAndClaimGauge(sender);
    _withdrawTranchee();
    _removeLiquidity(_minAmounts);
    _transferUnderlyingToken(sender);
  }


  function _removeLiquidity(uint256[2] memory _minAmounts) internal {
    uint256 _balanceCRVToken = CrvLPToken.balanceOf(address(this));
    CrvPool.remove_liquidity(_balanceCRVToken, _minAmounts);
  }

  function token() external view returns (IERC20[] memory) {
    return _tokens();
  }
  
  function stakedToken() external view returns (address){
    return _stakedToken();
  }

}