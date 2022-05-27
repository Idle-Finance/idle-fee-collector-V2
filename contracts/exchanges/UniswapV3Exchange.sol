// SPDX-License-Identifier: MIT
pragma solidity = 0.8.14;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IExchange.sol";

contract UniswapV3Exchange is IExchange, Ownable {
  using SafeERC20 for IERC20;

  ISwapRouter private immutable uniswapRouterV3;
  IQuoter private immutable uniswapQuoterV3;
  IUniswapV3Factory private immutable uniswapFactoryV3;

  uint24[] private poolFees; 

  constructor(address _router, address _quoter, address _factory) {

    uniswapRouterV3 = ISwapRouter(_router);
    uniswapQuoterV3 = IQuoter(_quoter);
    uniswapFactoryV3 = IUniswapV3Factory(_factory);

    poolFees = new uint24[](3); 
    poolFees[0] = 500;
    poolFees[1] = 3000;
    poolFees[2] = 10000;

  }

  function exchange(address token, uint amountMinOut, address to, address[] calldata path, bytes calldata data) external override onlyOwner returns(uint256 amountOut) {

    uint256 _amountIn = IERC20(token).balanceOf(address(this));

    address _tokenIn = path[0];
    address _tokenOut = path[1];

    uint24 poolFee;

    (poolFee)= abi.decode(data, (uint24));

    ISwapRouter.ExactInputSingleParams memory params =  ISwapRouter.ExactInputSingleParams({
        tokenIn: _tokenIn,
        tokenOut: _tokenOut,
        fee: poolFee,
        recipient: to,
        deadline: block.timestamp + 1800,
        amountIn: _amountIn,
        amountOutMinimum: amountMinOut,
        sqrtPriceLimitX96: 0
    });

    amountOut = uniswapRouterV3.exactInputSingle(params);
  }

  function getAmoutOut(address tokenA, address tokenB, uint amountIn) public override onlyOwner returns (uint amountOut, bytes memory data) {
    uint256 _amountOut;
    uint256 _maxAmountOut = 0;
    uint24 _fee;
    uint24[] memory _poolFees = poolFees;

    for (uint8 index = 0; index < _poolFees.length; ++index) {
      if (uniswapFactoryV3.getPool(tokenA, tokenB, _poolFees[index]) == address(0)) {
        continue;
      }
      _amountOut =  uniswapQuoterV3.quoteExactInputSingle(tokenA, tokenB, _poolFees[index], amountIn, 0);

      if (_amountOut > _maxAmountOut)  {
        _maxAmountOut = _amountOut;
        _fee = _poolFees[index];
      }
    }

    amountOut = _maxAmountOut;
    data = abi.encode(_fee);
  }

  function approveToken(address _depositToken, uint256 amount) external override  onlyOwner {
    IERC20(_depositToken).safeIncreaseAllowance(address(uniswapRouterV3), amount);
  }

  function removeApproveToken(address _token) external override onlyOwner {
    IERC20(_token).safeApprove(address(uniswapRouterV3), 0);
  }
}
