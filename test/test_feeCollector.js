const {BN, constants, expectRevert} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const FeeCollector = artifacts.require('FeeCollector')
const IUniswapV2Router02 = artifacts.require('IUniswapV2Router02')
const UniswapV2Exchange = artifacts.require('UniswapV2Exchange')
const UniswapV3Exchange = artifacts.require('UniswapV3Exchange')
const StakeAaveManager = artifacts.require('StakeAaveManager')
const StakeStEthTranchesManager = artifacts.require('StakeStEthTranchesManager')
const StakeCrvTranchesManager = artifacts.require('StakeCrvTranchesManager')
const IWETH = artifacts.require('IWETH')

const mockERC20 = artifacts.require('ERC20Mock')

const IStakedAave = artifacts.require('IStakedAave')
const IDepositZap = artifacts.require('IDepositZap')
const IIdleCDO = artifacts.require('IIdleCDO')
const ILiquidityGaugeV3 = artifacts.require('ILiquidityGaugeV3')

const { increaseTo, increaseTime } = require('../utilities/rpc')
const { swap: swapUniswapV2 } = require('../utilities/exchanges/uniswapV2')
const { addLiquidity: addLiquidityUniswapV3 }= require('../utilities/exchanges/uniswapV3')
const {deployProxy} = require('../utilities/proxy')
const addresses = require("../constants/addresses").development
const { abi: ERC20abi } = require('@openzeppelin/contracts/build/contracts/ERC20.json');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

const BNify = n => new BN(String(n))
const TOKEN_DECIMALS = (decimals) => new BN('10').pow(new BN(decimals));
const HOUR_SEC = 60 * 60
const WEEK_SEC = 60 * 60 * 24 * 7

contract("FeeCollector", async accounts => {
  beforeEach(async function(){
    const [feeCollectorOwner, proxyOwner, otherAddress] = accounts
    this.feeCollectorOwner = feeCollectorOwner
    this.proxyOwner = proxyOwner
    this.otherAddress = otherAddress

    this.provider = web3.currentProvider.HttpProvider

    this.zeroAddress = "0x0000000000000000000000000000000000000000"
    this.nonZeroAddress = "0x0000000000000000000000000000000000000001"
    this.nonZeroAddress2 = "0x0000000000000000000000000000000000000002"

    this.one = BNify('1000000000000000000')
    this.ratio_one_pecrent = BNify('1000')

    this.Weth = await IWETH.at(addresses.weth)
    this.mockDAI  = await mockERC20.new('DAI', 'DAI', 18)
    this.mockIDLE  = await mockERC20.new('IDLE', 'IDLE', 18)
    this.mockUSDC  = await mockERC20.new('USDC', 'USDC', 6)

    this.aaveInstance = new web3.eth.Contract(ERC20abi, addresses.aave)
    this.stakeAaveInstance = await IStakedAave.at(addresses.stakeAave)

    await this.Weth.approve(addresses.uniswapRouterAddress, constants.MAX_UINT256)
    await this.mockDAI.approve(addresses.uniswapRouterAddress, constants.MAX_UINT256)
    await this.mockUSDC.approve(addresses.uniswapRouterAddress, constants.MAX_UINT256)
    await this.aaveInstance.methods.approve(addresses.uniswapRouterAddress, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    
    this.uniswapRouterInstance = await IUniswapV2Router02.at(addresses.uniswapRouterAddress);

    await this.Weth.deposit({value: web3.utils.toWei("0.001"), from: this.feeCollectorOwner})
    const wethBalance = await this.Weth.balanceOf(this.feeCollectorOwner)
    
    await this.uniswapRouterInstance.addLiquidity(
      this.Weth.address, this.mockDAI.address,
      wethBalance, web3.utils.toWei("200"),
      0, 0,
      this.feeCollectorOwner,
      BNify(web3.eth.getBlockNumber())
    )
  
    this.stakeManager = await StakeAaveManager.new(addresses.aave, addresses.stakeAave)
    this.exchangeManager = await UniswapV2Exchange.new(addresses.uniswapFactory, addresses.uniswapRouterAddress)

    const initializationArgs = [
      [addresses.feeTreasuryAddress, addresses.idleRebalancer],
      [80000, 20000],
      [],
      [this.exchangeManager.address],
      [{_stakeManager: this.stakeManager.address, _isTrancheToken: false}]
    ]

    const {implementationInstance, TransparentUpgradableProxy} = await deployProxy(FeeCollector,initializationArgs, this.proxyOwner, this.feeCollectorOwner)
    this.TransparentUpgradableProxy = TransparentUpgradableProxy
    this.feeCollectorInstance = implementationInstance

    await this.stakeManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    await this.exchangeManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
  })

  it("Should replace proxy admin", async function () {
    const adminBefore = await this.TransparentUpgradableProxy.admin.call({from: this.proxyOwner})
    await this.TransparentUpgradableProxy.changeAdmin(this.otherAddress, {from: this.proxyOwner})
    const adminAfter = await this.TransparentUpgradableProxy.admin.call({from: this.otherAddress})
    expect(adminAfter).to.not.eq(adminBefore)
  })
    
  it("Should upgrade the contract implementation", async function () {
    const implementationBefore = await this.TransparentUpgradableProxy.implementation.call({from: this.proxyOwner})
    await this.TransparentUpgradableProxy.upgradeTo(this.feeCollectorInstance.address, {from: this.proxyOwner})
    const implementationAfter = await this.TransparentUpgradableProxy.implementation.call({from: this.proxyOwner})
    expect(implementationAfter).to.not.eq(implementationBefore)
  })

  it("Should correctly deploy", async function() {
    let allocation = await this.feeCollectorInstance.getSplitAllocation.call()

    let deployerAddressWhitelisted = await this.feeCollectorInstance.isAddressWhitelisted.call(this.feeCollectorOwner)
    let randomAddressWhitelisted = await this.feeCollectorInstance.isAddressWhitelisted.call(this.otherAddress)
    let deployerAddressAdmin = await this.feeCollectorInstance.isAddressAdmin.call(this.feeCollectorOwner)
    let randomAddressAdmin = await this.feeCollectorInstance.isAddressAdmin.call(this.otherAddress)

    let beneficiaries = await this.feeCollectorInstance.getBeneficiaries.call()

    let depositTokens = await this.feeCollectorInstance.getDepositTokens.call()

    expect(depositTokens.length).to.be.equal(0)
    
    expect(allocation.length).to.be.equal(2)

    expect(allocation[0], "Initial ratio is not set to 15%").to.be.bignumber.equal(BNify('80000'))
    expect(allocation[1], "Initial ratio is not set to 5%").to.be.bignumber.equal(BNify('20000'))

    assert.isTrue(deployerAddressWhitelisted, "Deployer account should be whitelisted")
    assert.isFalse(randomAddressWhitelisted, "Random account should not be whitelisted")

    assert.isTrue(deployerAddressAdmin, "Deployer account should be admin")
    assert.isFalse(randomAddressAdmin, "Random account should not be admin")

    assert.equal(beneficiaries[0].toLowerCase(), addresses.feeTreasuryAddress.toLowerCase())
    assert.equal(beneficiaries[1].toLowerCase(), addresses.idleRebalancer.toLowerCase())
  })

  it("Should deposit tokens with split set to 50/50", async function() {

    await this.feeCollectorInstance.setSplitAllocation([this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))])

    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address)

    const depositTokens = await this.feeCollectorInstance.getDepositTokens.call()
    expect(depositTokens.length).to.be.equal(1)

    const feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    const depositAmount = web3.utils.toWei("500")
    await this.mockDAI.transfer(this.feeCollectorInstance.address, depositAmount)
    const depositTokensEnabled = [true]
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(depositTokensEnabled, [0], managers, data) 
    
    const feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    const feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    const idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(feeTreasuryWethBalanceDiff).to.be.bignumber.equal(idleRebalancerWethBalanceDiff)
  })

  it("Should cloud stake and unstake aave token and deposit tokens with split set to 50/50", async function() {
    const COOLDOWN_SECONDS = new BN(await this.stakeAaveInstance.COOLDOWN_SECONDS())

    await swapUniswapV2(15, addresses.aave, addresses.weth, this.provider, this.feeCollectorOwner)

    let amountToStkAave = web3.utils.toWei('1')

    await this.aaveInstance.methods.approve(addresses.stakeAave, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    
    await this.stakeAaveInstance.stake(this.feeCollectorOwner, amountToStkAave, {from: this.feeCollectorOwner, gasLimit: 400000})

    const stakeAaveBalance =  await this.stakeAaveInstance.balanceOf(this.feeCollectorOwner)
    
    await this.stakeAaveInstance.transfer(this.feeCollectorInstance.address, stakeAaveBalance, {from: this.feeCollectorOwner, gasLimit: 400000})
    
    const unstakeData = [{
      _stakeManager: this.stakeManager.address,
      _tokens: [{_address: addresses.stakeAave, _extraData: '0x'}]
    }]
    
    await this.feeCollectorInstance.claimStakedToken(unstakeData)
  
    let feeCollectorbalanceOfStkAave = await this.stakeAaveInstance.balanceOf(this.feeCollectorInstance.address)

    expect(feeCollectorbalanceOfStkAave.toNumber()).equal(0)

    let feeCollectorBalanceOfAave =  await this.aaveInstance.methods.balanceOf(this.feeCollectorInstance.address).call()
    
    await this.feeCollectorInstance.claimStakedToken(unstakeData)

    expect(+feeCollectorBalanceOfAave).equal(0)

    const stakersCooldown =  new BN(await this.stakeAaveInstance.stakersCooldowns(this.stakeManager.address))
    
    const cooldownOffset = new BN(1000)
    await increaseTo(stakersCooldown.add(COOLDOWN_SECONDS).add(cooldownOffset))
    
    await this.feeCollectorInstance.claimStakedToken(unstakeData)

    feeCollectorBalanceOfAave =  await this.aaveInstance.methods.balanceOf(this.feeCollectorInstance.address).call()
    stakeManagerbalanceOfStkAave = await this.stakeAaveInstance.balanceOf(this.stakeManager.address)

    expect(stakeManagerbalanceOfStkAave.toNumber()).equal(0)

    await this.feeCollectorInstance.setSplitAllocation([this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))], {from: this.feeCollectorOwner}) 

    await this.feeCollectorInstance.registerTokenToDepositList(this.aaveInstance._address)

    const feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    const depositTokensEnabled = [true]

    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(depositTokensEnabled, [0],  managers, data, {from: this.feeCollectorOwner})

    const feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    const feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    const idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.closeTo(feeTreasuryWethBalanceDiff, TOKEN_DECIMALS(18))
  })

  it("Should unstake MIM tranche tokens and deposit tokens with split set to 50/50", async function () {
    const tokenContract = new web3.eth.Contract(ERC20abi, addresses.mim)

    await swapUniswapV2(1, tokenContract._address, addresses.weth, this.provider, this.feeCollectorOwner)

    const balance = await tokenContract.methods.balanceOf(this.feeCollectorOwner).call()
    const depositArray = [balance, 0, 0, 0]
    const minLpTokens = 0
    const depositZap = await IDepositZap.at(addresses.depositZap)
    await tokenContract.methods.approve(depositZap.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await depositZap.add_liquidity(addresses.MIM3CRVpool, depositArray, minLpTokens, {from: this.feeCollectorOwner});

    const underlyingToken = new web3.eth.Contract(ERC20abi, addresses.MIM3CRV)
    const tranche = await IIdleCDO.at(addresses.MIM3CRVTranche)
    const balanceUnderlyingToken = await underlyingToken.methods.balanceOf(this.feeCollectorOwner).call()
    await underlyingToken.methods.approve(tranche.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await tranche.depositAA(balanceUnderlyingToken)

    const AATranche = await tranche.AATranche()
    const AATrancheContract = new web3.eth.Contract(ERC20abi, AATranche)
    const balanceAATrancheToken = await AATrancheContract.methods.balanceOf(this.feeCollectorOwner).call()
    const gauge = await ILiquidityGaugeV3.at(addresses.mimGauge)
    await AATrancheContract.methods.approve(gauge.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await gauge.deposit(balanceAATrancheToken, this.feeCollectorOwner, false)

    const balanceGaugeToken = await gauge.balanceOf(this.feeCollectorOwner)
    await gauge.transfer(this.feeCollectorInstance.address, balanceGaugeToken)

    const underlyingTokens = [[addresses.mim, addresses.crv3]]
    const stakeTranchesManager = await StakeCrvTranchesManager.new([gauge.address], underlyingTokens, [tranche.address], [addresses.MIM3CRVpool], [addresses.MIM3CRV])
    await stakeTranchesManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    const stakeManager = {_stakeManager: stakeTranchesManager.address, _isTrancheToken: true}
    await this.feeCollectorInstance.addStakeManager(stakeManager)

    const uniswapV3Exchange = await UniswapV3Exchange.new(addresses.swapRouter, addresses.quoter, addresses.uniswapV3FactoryAddress)
    await uniswapV3Exchange.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    await this.feeCollectorInstance.addExchangeManager(uniswapV3Exchange.address, {from: this.feeCollectorOwner})

    await increaseTime(WEEK_SEC * 2)
    const claimData = web3.eth.abi.encodeParameter('uint256[2]', [0,0]);

    const unstakeData = [{
      _stakeManager: stakeTranchesManager.address,
      _tokens: [{_address: gauge.address, _extraData: claimData}]
    }]

    await this.feeCollectorInstance.claimStakedToken(unstakeData)

    await this.feeCollectorInstance.setSplitAllocation([this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))])

    const feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    const tokens = [...underlyingTokens[0], addresses.idle]
    const depositTokens = tokens.map((token) => new web3.eth.Contract(ERC20abi, token))
    const rewardToken = depositTokens[2]
    const rewardBalance = await rewardToken.methods.balanceOf(this.feeCollectorInstance.address).call()
    // if token balance < 1000 adds more balance to allow swap
    if (rewardBalance < 1000) {
      await swapUniswapV2(1, rewardToken._address, addresses.weth, this.provider, this.feeCollectorOwner)
      await rewardToken.methods.transfer(this.feeCollectorInstance.address, '1000').send({from: this.feeCollectorOwner})
    }

    for (const token of depositTokens) {
      await this.feeCollectorInstance.registerTokenToDepositList(token._address)
    }
    const depositTokensEnabled = await Promise.all(depositTokens.map(async (depositToken) => await depositToken.methods.balanceOf(this.feeCollectorInstance.address).call().then(v => new BN(v).gt(new BN('0')))))
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    const minTokenOut = depositTokens.map(() => 0)
    await this.feeCollectorInstance.deposit(depositTokensEnabled, minTokenOut,  managers, data, {from: this.feeCollectorOwner})

    const feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    const feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    const idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.closeTo(feeTreasuryWethBalanceDiff, TOKEN_DECIMALS(18))
  })

  it("Should unstake FRAX3CRV tranche tokens and deposit tokens with split set to 50/50", async function () {
    const tokenContract = new web3.eth.Contract(ERC20abi, addresses.frax)

    await swapUniswapV2(1, tokenContract._address, addresses.weth, this.provider, this.feeCollectorOwner)
    const balance = await tokenContract.methods.balanceOf(this.feeCollectorOwner).call()

    const depositArray = [balance, 0, 0, 0]
    const minLpTokens = 0
    const depositZap = await IDepositZap.at(addresses.depositZap)
    await tokenContract.methods.approve(depositZap.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await depositZap.add_liquidity(addresses.FRAX3CRVpool, depositArray, minLpTokens, {from: this.feeCollectorOwner});

    const underlyingToken = new web3.eth.Contract(ERC20abi, addresses.FRAX3CRV)
    const tranche = await IIdleCDO.at(addresses.FRAX3CrvTranche)
    const balanceUnderlyingToken = await underlyingToken.methods.balanceOf(this.feeCollectorOwner).call()
    await underlyingToken.methods.approve(tranche.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await tranche.depositAA(balanceUnderlyingToken)

    const AATranche = await tranche.AATranche()
    const AATrancheContract = new web3.eth.Contract(ERC20abi, AATranche)
    const balanceAATrancheToken = await AATrancheContract.methods.balanceOf(this.feeCollectorOwner).call()
    const gauge = await ILiquidityGaugeV3.at(addresses.fraxGauge)
    await AATrancheContract.methods.approve(gauge.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await gauge.deposit(balanceAATrancheToken, this.feeCollectorOwner, false)

    const balanceGaugeToken = await gauge.balanceOf(this.feeCollectorOwner)
    await gauge.transfer(this.feeCollectorInstance.address, balanceGaugeToken)

    const underlyingTokens = [[addresses.frax, addresses.crv3]]
    const stakeTranchesManager = await StakeCrvTranchesManager.new([gauge.address], underlyingTokens, [tranche.address], [addresses.FRAX3CRVpool], [addresses.FRAX3CRV])

    await stakeTranchesManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})

    const stakeManager = {_stakeManager: stakeTranchesManager.address, _isTrancheToken: true}
    await this.feeCollectorInstance.addStakeManager(stakeManager)

    await increaseTime(HOUR_SEC * 2)
    const claimData = web3.eth.abi.encodeParameter('uint256[2]', [0,0]);

    const unstakeData = [{
      _stakeManager: stakeTranchesManager.address,
      _tokens: [{_address: gauge.address, _extraData: claimData}]
    }]
    await this.feeCollectorInstance.claimStakedToken(unstakeData)

    await this.feeCollectorInstance.setSplitAllocation([this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))])

    const feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    const tokens = [...underlyingTokens[0], addresses.idle]
    const depositTokens = tokens.map((token) => new web3.eth.Contract(ERC20abi, token))
    for (const token of depositTokens) {
      await this.feeCollectorInstance.registerTokenToDepositList(token._address)      
    }
    const depositTokensEnabled = await Promise.all(depositTokens.map(async (depositToken) => await depositToken.methods.balanceOf(this.feeCollectorInstance.address).call().then(v => new BN(v).gt(new BN('0')))))
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    const minTokenOut = depositTokens.map(() => 0)
    await this.feeCollectorInstance.deposit(depositTokensEnabled, minTokenOut,  managers, data, {from: this.feeCollectorOwner})

    const feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    const feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    const idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.closeTo(feeTreasuryWethBalanceDiff, TOKEN_DECIMALS(18))
  })

  it("Should unstake stEth tranche tokens  and deposit tokens with split set to 50/50", async function () {
    const underlyingToken = new web3.eth.Contract(ERC20abi, addresses.steth)

    await swapUniswapV2(1, underlyingToken._address, addresses.weth, this.provider, this.feeCollectorOwner)
    
    const balanceUnderlyingToken = await underlyingToken.methods.balanceOf(this.feeCollectorOwner).call()
    const tranche = await IIdleCDO.at(addresses.STETHTranche)
    await underlyingToken.methods.approve(tranche.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await tranche.depositAA(balanceUnderlyingToken)

    const AATranche = await tranche.AATranche()
    const AATrancheContract = new web3.eth.Contract(ERC20abi, AATranche)
    const balanceAATrancheToken = new BN(await AATrancheContract.methods.balanceOf(this.feeCollectorOwner).call())
    const gauge = await ILiquidityGaugeV3.at(addresses.stethGauge)
    await AATrancheContract.methods.approve(gauge.address, constants.MAX_UINT256).send({from: this.feeCollectorOwner})
    await gauge.deposit(balanceAATrancheToken.div(new BN(2)), this.feeCollectorOwner, false)

    const balanceGaugeToken = await gauge.balanceOf(this.feeCollectorOwner)
    await gauge.transfer(this.feeCollectorInstance.address, balanceGaugeToken)

    // wait 2 hours
    await increaseTime(HOUR_SEC * 2)
  
    // other user deposit
    await AATrancheContract.methods.transfer(this.otherAddress, balanceAATrancheToken.div(new BN(2))).send({from: this.feeCollectorOwner})
    await AATrancheContract.methods.approve(gauge.address, constants.MAX_UINT256).send({from: this.otherAddress})
    const balanceOther = await AATrancheContract.methods.balanceOf(this.otherAddress).call()

    await gauge.deposit(balanceOther, this.otherAddress, false, {from: this.otherAddress})
    
    // wait 2 hours
    await increaseTime(HOUR_SEC * 2)
    
    const rewardsTokens = [addresses.lido, addresses.idle]
    const underlyingTokens = [[underlyingToken._address]]
    const stakeTranchesManager = await StakeStEthTranchesManager.new([gauge.address], underlyingTokens, [tranche.address])
    await stakeTranchesManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    const stakeManager = {_stakeManager: stakeTranchesManager.address, _isTrancheToken: true}
    await this.feeCollectorInstance.addStakeManager(stakeManager)
    const rewardsTokensContract = rewardsTokens.map((rewardToken) => new web3.eth.Contract(ERC20abi, rewardToken))

    const unstakeData = [{
      _stakeManager: stakeTranchesManager.address,
      _tokens: [{_address: gauge.address, _extraData: '0x'}]
    }]
    await this.feeCollectorInstance.claimStakedToken(unstakeData)
    
    await this.feeCollectorInstance.setSplitAllocation([this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))])

    const feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    const depositTokens = [underlyingToken, ...rewardsTokensContract]
    for (const token of depositTokens) {
      await this.feeCollectorInstance.registerTokenToDepositList(token._address)
    }
    const depositTokensEnabled = await Promise.all(depositTokens.map(async (depositToken) => await depositToken.methods.balanceOf(this.feeCollectorInstance.address).call().then(v => new BN(v).gt(new BN('0')))))
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    const minTokenOut = depositTokens.map(() => 0)
    await this.feeCollectorInstance.deposit(depositTokensEnabled, minTokenOut,  managers, data, {from: this.feeCollectorOwner})

    const feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    const idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    const feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    const idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.closeTo(feeTreasuryWethBalanceDiff, TOKEN_DECIMALS(18))
  })

  it("Should add and remove a new stake token to CRV stake manager", async function() {
    const underlyingTokens = [[addresses.frax, addresses.crv3]]
    const stakeTranchesManager = await StakeCrvTranchesManager.new([addresses.fraxGauge], underlyingTokens, [addresses.FRAX3CrvTranche], [addresses.FRAX3CRVpool], [addresses.FRAX3CRV])
    await stakeTranchesManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    const stakeManager = {_stakeManager: stakeTranchesManager.address, _isTrancheToken: true}
    await this.feeCollectorInstance.addStakeManager(stakeManager)

    await this.feeCollectorInstance.addStakedToken(stakeTranchesManager.address, addresses.mimGauge, addresses.MIM3CRVTranche, [addresses.mim, addresses.crv3], addresses.MIM3CRVpool, addresses.MIM3CRV)
    
    let stkedTokens = await stakeTranchesManager.stakedTokens.call()
    expect(stkedTokens.length).to.be.equal(2)
    
    await this.feeCollectorInstance.removeStakedToken(stakeTranchesManager.address, 1, addresses.mimGauge)
    stkedTokens = await stakeTranchesManager.stakedTokens.call()
    expect(stkedTokens.length).to.be.equal(1)
  })

  it("Should add a new Stake Manager", async function() {
    let stakeManagers = await this.feeCollectorInstance.getStakeeManagers()
    expect(stakeManagers.length).eq(1)

    const newStakeManager = await StakeAaveManager.new(addresses.aave, addresses.stakeAave)
    const stakeManager = {_stakeManager: newStakeManager.address, _isTrancheToken: false}
    await this.feeCollectorInstance.addStakeManager(stakeManager)
    stakeManagers = await this.feeCollectorInstance.getStakeeManagers()
    expect(stakeManagers.length).eq(2)
  })

  it("Should remove a Stake Manager", async function() {
    let stakeManagers = await this.feeCollectorInstance.getStakeeManagers()
    expect(stakeManagers.length).eq(1)

    const removeStakeManagerTx = this.feeCollectorInstance.removeStakeManager(0)
    await expectRevert(removeStakeManagerTx, 'Cannot remove the last stake manager')

    const newStakeManager = await StakeAaveManager.new(addresses.aave, addresses.stakeAave)
    const stakeManager = {_stakeManager: newStakeManager.address, _isTrancheToken: false}
    await this.feeCollectorInstance.addStakeManager(stakeManager)
    stakeManagers = await this.feeCollectorInstance.getStakeeManagers()
    expect(stakeManagers.length).eq(2)
    
    await this.feeCollectorInstance.removeStakeManager(0)
    stakeManagers = await this.feeCollectorInstance.getStakeeManagers()
    expect(stakeManagers.length).eq(1)
  })
  it("Should change the Exchange Manager and deposit tokens with split set to 50/50", async function () {

    await this.Weth.deposit({value: web3.utils.toWei("0.001"), from: this.feeCollectorOwner})
    const wethBalance = await this.Weth.balanceOf(this.feeCollectorOwner)
    await addLiquidityUniswapV3(this.mockDAI.address, this.Weth.address, 500, this.feeCollectorOwner, wethBalance)

    await this.feeCollectorInstance.setSplitAllocation( [this.ratio_one_pecrent.mul(BNify('50')), this.ratio_one_pecrent.mul(BNify('50'))], {from: this.feeCollectorOwner})
    
    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address, {from: this.feeCollectorOwner}) 
    
    const uniswapV3Exchange = await UniswapV3Exchange.new(addresses.swapRouter, addresses.quoter, addresses.uniswapV3FactoryAddress)
    
    await uniswapV3Exchange.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})

    await this.feeCollectorInstance.addExchangeManager(uniswapV3Exchange.address, {from: this.feeCollectorOwner})

    let feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    let depositAmount = web3.utils.toWei("50")
    await this.mockDAI.transfer(this.feeCollectorInstance.address, depositAmount, {from: this.feeCollectorOwner})
    const depositTokensEnabled = [true]
    
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(depositTokensEnabled, [0],managers, data, {from: this.feeCollectorOwner})

    let feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))

    let feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    let idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)

    expect(feeTreasuryWethBalanceDiff).to.be.bignumber.equal(idleRebalancerWethBalanceDiff)
  })
  it("Should add a new Exchange Manager", async function() {
    let exchangeManagers = await this.feeCollectorInstance.getExchangeManagers()
    expect(exchangeManagers.length).eq(1)

    const newExchangeManager = await UniswapV3Exchange.new(addresses.swapRouter, addresses.quoter, addresses.uniswapV3FactoryAddress)
    await this.feeCollectorInstance.addExchangeManager(newExchangeManager.address)
    exchangeManagers = await this.feeCollectorInstance.getExchangeManagers()
    expect(exchangeManagers.length).eq(2)
  })

  it("Should remove an Exchange Manager", async function() {
    let exchangeManagers = await this.feeCollectorInstance.getExchangeManagers()
    expect(exchangeManagers.length).eq(1)

    const removeExchangeTx = this.feeCollectorInstance.removeExchangeManager(0)
    await expectRevert(removeExchangeTx, 'Cannot remove the last exchange')

    const newExchangeManager = await UniswapV3Exchange.new(addresses.swapRouter, addresses.quoter, addresses.uniswapV3FactoryAddress)
    await this.feeCollectorInstance.addExchangeManager(newExchangeManager.address)
    exchangeManagers = await this.feeCollectorInstance.getExchangeManagers()
    expect(exchangeManagers.length).eq(2)
    
    await this.feeCollectorInstance.removeExchangeManager(0)
    exchangeManagers = await this.feeCollectorInstance.getExchangeManagers()
    expect(exchangeManagers.length).eq(1)
  })

  it("Should deposit with max fee tokens and max beneficiaries", async function() {
    let initialAllocation = [BNify('90'), BNify('5')]

    for (let index = 0; index <= 2; index++) {
      initialAllocation[0] = BNify(90-5*index)
      initialAllocation.push(BNify('5'))
      
      let allocation = initialAllocation.map(x => this.ratio_one_pecrent.mul(x))
      await this.feeCollectorInstance.addBeneficiaryAddress(accounts[index], allocation)
    }
    let tokensEnables = [];
    let minTokenBalance = []


    for (let index = 0; index < 15; index++) {
      let token = await mockERC20.new('Token', 'TKN', 18)
      await this.feeCollectorInstance.registerTokenToDepositList(token.address)
      await token.approve(addresses.uniswapRouterAddress, constants.MAX_UINT256)

      await this.Weth.deposit({value: web3.utils.toWei("0.001"), from: this.feeCollectorOwner})
      const wethBalance = await this.Weth.balanceOf(this.feeCollectorOwner)

      await this.uniswapRouterInstance.addLiquidity(
        this.Weth.address, token.address,
        wethBalance, web3.utils.toWei("60000"),
        0, 0,
        this.feeCollectorOwner,
        BNify(web3.eth.getBlockNumber())
      )

      let depositAmount = web3.utils.toWei("50")
      await token.transfer(this.feeCollectorInstance.address, depositAmount, {from: this.feeCollectorOwner})
      tokensEnables.push(true);
      minTokenBalance.push(1)
    }

    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(tokensEnables)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(tokensEnables, minTokenBalance, managers, data)
  })

  it('Should not be able to add duplicate beneficiaries', async function() {
    let allocationA = [this.ratio_one_pecrent.mul(BNify('100')), BNify('0'), BNify('0')]

    await this.feeCollectorInstance.addBeneficiaryAddress(this.otherAddress, allocationA)

    await expectRevert(this.feeCollectorInstance.addBeneficiaryAddress(this.otherAddress, allocationA), "Duplicate beneficiary")
  })

  it("Should remove beneficiary", async function() {
    let allocation = [this.ratio_one_pecrent.mul(BNify('100')), BNify('0'), BNify('0')]

    await this.feeCollectorInstance.addBeneficiaryAddress(this.otherAddress, allocation)

    let beneficiaries = await this.feeCollectorInstance.getBeneficiaries.call()

    expect(beneficiaries.length).to.be.equal(3)

    allocation.pop()
    await this.feeCollectorInstance.removeBeneficiaryAt(1, allocation)

    beneficiaries = await this.feeCollectorInstance.getBeneficiaries.call()

    expect(beneficiaries.length).to.be.equal(2)
    expect(beneficiaries[1].toLowerCase()).to.be.equal(this.otherAddress.toLowerCase())
  })

  it("Should respect previous allocation when removing beneficiary", async function() {

    let allocation = [
      this.ratio_one_pecrent.mul(BNify('50')),
      this.ratio_one_pecrent.mul(BNify('25')),
      this.ratio_one_pecrent.mul(BNify('25')),
    ]

    await this.feeCollectorInstance.addBeneficiaryAddress(this.otherAddress, allocation)
    
    let beneficiaryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(this.otherAddress))
    let feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    let newAllocation = [
      this.ratio_one_pecrent.mul(BNify('50')),
      this.ratio_one_pecrent.mul(BNify('50')),
      this.ratio_one_pecrent.mul(BNify('0'))
    ]
    await this.feeCollectorInstance.setSplitAllocation(newAllocation, {from: this.feeCollectorOwner})

    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address)

    let depositAmount = web3.utils.toWei("50")
    await this.mockDAI.transfer(this.feeCollectorInstance.address, depositAmount, {from: this.feeCollectorOwner})

    const depositTokensEnabled = [true]
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(depositTokensEnabled, [0], managers, data, {from: this.feeCollectorOwner})

    let beneficiaryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(this.otherAddress))
    let feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceAfter =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    
    let beneficiaryWethBalanceDiff = beneficiaryWethBalanceAfter.sub(beneficiaryWethBalanceBefore)
    let idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)
    let feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    
    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.equal(feeTreasuryWethBalanceDiff)
    expect(beneficiaryWethBalanceDiff).to.be.bignumber.equal(BNify("0"))
  })

  it("Should respect previous allocation when adding beneficiary", async function() {

    let allocation = [
      this.ratio_one_pecrent.mul(BNify('50')),
      this.ratio_one_pecrent.mul(BNify('50')),
    ]
    await this.feeCollectorInstance.setSplitAllocation(allocation)

    let feeTreasuryWethBalanceBefore = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    let beneficiaryWethBalanceBefore =  BNify(await this.Weth.balanceOf.call(this.otherAddress))
    
    let newAllocation = [
      this.ratio_one_pecrent.mul(BNify('50')),
      this.ratio_one_pecrent.mul(BNify('25')),
      this.ratio_one_pecrent.mul(BNify('25')),
    ]

    await this.feeCollectorInstance.addBeneficiaryAddress(this.otherAddress, newAllocation)

    let depositAmount = web3.utils.toWei("50")
    await this.mockDAI.transfer(this.feeCollectorInstance.address, depositAmount, {from: this.feeCollectorOwner})
    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address)

    const depositTokensEnabled = [true]
    const previewDeposit = await this.feeCollectorInstance.previewDeposit.call(depositTokensEnabled)
    const managers = previewDeposit[0]
    const data = previewDeposit[1]
    await this.feeCollectorInstance.deposit(depositTokensEnabled, [0], managers, data, {from: this.feeCollectorOwner})

    let feeTreasuryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.feeTreasuryAddress))
    let idleRebalancerWethBalanceAfter = BNify(await this.Weth.balanceOf.call(addresses.idleRebalancer))
    let beneficiaryWethBalanceAfter = BNify(await this.Weth.balanceOf.call(this.otherAddress))

    let idleRebalancerWethBalanceDiff = idleRebalancerWethBalanceAfter.sub(idleRebalancerWethBalanceBefore)
    let feeTreasuryWethBalanceDiff = feeTreasuryWethBalanceAfter.sub(feeTreasuryWethBalanceBefore)
    let beneficiaryWethBalanceDiff = beneficiaryWethBalanceAfter.sub(beneficiaryWethBalanceBefore)

    expect(idleRebalancerWethBalanceDiff).to.be.bignumber.equal(beneficiaryWethBalanceDiff) 
    expect(feeTreasuryWethBalanceDiff).to.be.bignumber.gt(beneficiaryWethBalanceDiff) 
    expect(feeTreasuryWethBalanceDiff).to.be.bignumber.gt(idleRebalancerWethBalanceDiff) 
  })

  it("Should revert when calling function with onlyWhitelisted modifier from non-whitelisted address", async function() {

    await expectRevert(this.feeCollectorInstance.deposit([], [],[], [], {from: this.otherAddress}), "Unauthorised") // call deposit
  })

  it("Should revert when calling function with onlyAdmin modifier when not admin", async function() {

    let allocation = [
      this.ratio_one_pecrent.mul(BNify('100')),
      this.ratio_one_pecrent.mul(BNify('0')),
      this.ratio_one_pecrent.mul(BNify('0')),
    ]
    
    await expectRevert(this.feeCollectorInstance.addBeneficiaryAddress(this.nonZeroAddress, allocation, {from: this.otherAddress}), "Unauthorised")
    await expectRevert(this.feeCollectorInstance.removeBeneficiaryAt(1, allocation, {from: this.otherAddress}), "Unauthorised")

    await expectRevert(this.feeCollectorInstance.addAddressToWhiteList(this.nonZeroAddress, {from: this.otherAddress}), "Unauthorised")
    await expectRevert(this.feeCollectorInstance.removeAddressFromWhiteList(this.nonZeroAddress, {from: this.otherAddress}), "Unauthorised")
    
    await expectRevert(this.feeCollectorInstance.registerTokenToDepositList(this.nonZeroAddress, {from: this.otherAddress}), "Unauthorised")
    await expectRevert(this.feeCollectorInstance.removeTokenFromDepositList(0, {from: this.otherAddress}), "Unauthorised")
    
    await expectRevert(this.feeCollectorInstance.setSplitAllocation(allocation, {from: this.otherAddress}), "Unauthorised")
    await expectRevert(this.feeCollectorInstance.replaceAdmin(this.nonZeroAddress, {from: this.otherAddress}), "Unauthorised")
  })

  it("Should add & remove a token from the deposit list", async function() {

    let isDaiInDepositListFromBootstrap = await this.feeCollectorInstance.isTokenInDespositList.call(this.mockDAI.address)
    assert.isFalse(isDaiInDepositListFromBootstrap)

    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address, {from: this.feeCollectorOwner})
    
    let daiInDepositList = await this.feeCollectorInstance.isTokenInDespositList.call(this.mockDAI.address)
    assert.isTrue(daiInDepositList)
    
    const depositTokens = await this.feeCollectorInstance.getDepositTokens()
    const mockDAIIndex = depositTokens.findIndex(token => token === this.mockDAI.address)

    await this.feeCollectorInstance.removeTokenFromDepositList(mockDAIIndex, {from: this.feeCollectorOwner})
    let daiNoLongerInDepositList = await this.feeCollectorInstance.isTokenInDespositList.call(this.mockDAI.address)
    assert.isFalse(daiNoLongerInDepositList)
  })

  it("Should add & remove whitelist address", async function() {

    let before = await this.feeCollectorInstance.isAddressWhitelisted(this.nonZeroAddress)
    expect(before, "Address should not be whitelisted initially").to.be.false

    await this.feeCollectorInstance.addAddressToWhiteList(this.nonZeroAddress, {from: this.feeCollectorOwner})
    let after = await this.feeCollectorInstance.isAddressWhitelisted(this.nonZeroAddress)
    expect(after, "Address should now be whitelisted").to.be.true

    await this.feeCollectorInstance.removeAddressFromWhiteList(this.nonZeroAddress, {from: this.feeCollectorOwner})
    let final = await this.feeCollectorInstance.isAddressWhitelisted(this.nonZeroAddress)
    expect(final, "Address should not be whitelisted").to.be.false
  })

  it("Should withdraw arbitrary token", async function() {

    let depositAmount = web3.utils.toWei("500")

    await this.mockDAI.transfer(this.feeCollectorInstance.address, depositAmount, {from: this.feeCollectorOwner})

    await this.feeCollectorInstance.withdraw(this.mockDAI.address, this.nonZeroAddress, depositAmount)
    let daiBalance = await this.mockDAI.balanceOf.call(this.nonZeroAddress)

    expect(daiBalance).to.be.bignumber.equal(depositAmount)
  })
  it("Should withdraw tokens from AAVE Stake Manager", async function() {
    await swapUniswapV2(1, addresses.aave, addresses.weth, this.provider, this.feeCollectorOwner)
    const balance = await this.aaveInstance.methods.balanceOf(this.feeCollectorOwner).call()
    await this.aaveInstance.methods.transfer(this.stakeManager.address, balance).send({from: this.feeCollectorOwner, gasLimit: 400000})
    await this.feeCollectorInstance.withdrawFromStakeManager(this.stakeManager.address, addresses.stakeAave ,this.feeCollectorOwner, [balance,0])
    const balanceAfter = await this.aaveInstance.methods.balanceOf(this.feeCollectorOwner).call()
    expect(balanceAfter).to.be.bignumber.equal(balance)
  })

  it("Should withdraw tokens from STETH Stake Manager", async function() {
    await swapUniswapV2(1, addresses.steth, addresses.weth, this.provider, this.feeCollectorOwner)
    const steth = new web3.eth.Contract(ERC20abi, addresses.steth)
    const balance = await steth.methods.balanceOf(this.feeCollectorOwner).call()

    const underlyingTokens = [[addresses.steth]]
    const stakeTranchesManager = await StakeStEthTranchesManager.new([addresses.stethGauge], underlyingTokens, [addresses.STETHTranche])
    await stakeTranchesManager.transferOwnership(this.feeCollectorInstance.address, {from: this.feeCollectorOwner})
    const stakeManager = {_stakeManager: stakeTranchesManager.address, _isTrancheToken: true}
    await this.feeCollectorInstance.addStakeManager(stakeManager)

    await steth.methods.transfer(stakeTranchesManager.address, balance).send({from: this.feeCollectorOwner, gasLimit: 400000})
    await this.feeCollectorInstance.withdrawFromStakeManager(stakeTranchesManager.address, addresses.stethGauge, this.feeCollectorOwner, [balance])
    const balanceAfter = await steth.methods.balanceOf(this.feeCollectorOwner).call()
    expect(balanceAfter).to.be.bignumber.equal(balance)
  })

  it("Should replace admin", async function() {

    let nonZeroAddressIsAdmin = await this.feeCollectorInstance.isAddressAdmin.call(this.nonZeroAddress)
    await this.feeCollectorInstance.replaceAdmin(this.nonZeroAddress, {from: this.feeCollectorOwner})

    let nonZeroAddressIsAdminAfter = await this.feeCollectorInstance.isAddressAdmin.call(this.nonZeroAddress)
    let previousAdminRevoked = await this.feeCollectorInstance.isAddressAdmin.call(this.feeCollectorOwner)

    expect(nonZeroAddressIsAdmin, "Address should not start off as admin").to.be.false
    expect(nonZeroAddressIsAdminAfter, "Address should be granted admin").to.be.true
    expect(previousAdminRevoked, "Previous admin should be revoked").to.be.false
  })

  it("Should not be able to add duplicate deposit token", async function() {

    await this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address)
    await expectRevert(this.feeCollectorInstance.registerTokenToDepositList(this.mockDAI.address), "Duplicate deposit token")

    let totalDepositTokens = await this.feeCollectorInstance.getNumTokensInDepositList.call()
    expect(totalDepositTokens).to.be.bignumber.equal(BNify('1'))
  })

  it("Should not add WETH as deposit token", async function() {

    await expectRevert(this.feeCollectorInstance.registerTokenToDepositList(this.Weth.address), "WETH not supported")
  })

  it("Should not be able to add deposit tokens past limit", async function() {
    let token
    for (let index = 0; index < 15; index++) {
      token = await mockERC20.new('Token', 'TKN', 18)
      await this.feeCollectorInstance.registerTokenToDepositList(token.address)
    }

    token = await mockERC20.new('Token', 'TKN', 18)
    await expectRevert(this.feeCollectorInstance.registerTokenToDepositList(token.address), "Too many tokens")
  })

  it("Should not set invalid split ratio", async function() {
    
    let allocation = [this.ratio_one_pecrent.mul(BNify('100')), BNify('5'),]
    
    await expectRevert(this.feeCollectorInstance.setSplitAllocation(allocation), "Ratio does not equal 100000")
  })
})
