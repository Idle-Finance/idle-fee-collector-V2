pragma solidity >=0.6.0 <=0.8.14;

interface IStakeManager {
  struct StakeManager { 
    address _stakeManager;
    bool _isTrancheToken;
  }
  struct StakeToken {
    address _address;
    bytes _extraData;
  }
  struct UnstakeData {
    address _stakeManager;
    StakeToken[] _tokens;
  }
  function claimStaked(StakeToken[] calldata _stakeTokens) external;
  function stakedTokens() view external returns(address[] memory);
  function addStakedToken(address _gauge, address _tranche, address[] calldata _underlyingTokens, address _pool, address _lpTokens) external;
  function removeStakedToken(uint256 _index, address _gauge) external;
  function withdrawAdmin(address _stakeToken, address _toAddress, uint256[] calldata _amounts) external;
}