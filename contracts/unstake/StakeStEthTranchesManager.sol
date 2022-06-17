pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StakeManagerTranches.sol";

import "../interfaces/IStakeManager.sol";

contract StakeStEthTranchesManager is IStakeManager, Ownable, StakeManagerTranches {
  using SafeERC20 for IERC20;

  
  constructor (address _gauge, address[] memory _underlyingToken, address _tranches) StakeManagerTranches(_gauge, _underlyingToken, _tranches) {}

  function claimStaked(bytes calldata _extraDatas) external onlyOwner {
    _claimStaked();
  }

  function withdrawAdmin(address _toAddress, uint256[] calldata _amounts) external override onlyOwner {
    _withdrawAdmin(_toAddress, _amounts);
  }
  
  function _claimStaked() internal {
    address sender = msg.sender;
    uint256 balance = _gaugeBalance(sender);
    if (balance == 0) {
      return;
    }
    _claimRewards(sender);
    _claimIdle(sender);
    _withdrawAndClaimGauge(sender);
    _withdrawTranchee();
    _transferUnderlyingToken(sender);
  }

  function token() external view returns (IERC20 [] memory) {
    return _tokens();
  }
  
  function stakedToken() external view returns (address){
    return _stakedToken();
  }

}