// SPDX-License-Identifier: MIT
pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
  uint8 immutable tokenDecimals;

  constructor(string memory _name, string memory _symbol, uint8 _decimals)
    ERC20(_name, _symbol) {
        tokenDecimals = _decimals;
      _mint(msg.sender, 100_000 * 10**_decimals); // 100,000 tokens
  }

  function decimals() public view virtual override returns (uint8) {
        return tokenDecimals;
    }
}
