import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { constants } from 'ethers'

const uniswapFactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984'
const operatorAddress = '0xb8d843c8E6e0E90eD2eDe80550856b64da92ee30'

function getUniswapFactoryAddress(network: string) {
  switch (network) {
    case 'goerliArbitrumEth':
      return '0xE54143413A7c1407D010f2B68A227be69df2CbFD'
    default:
      return uniswapFactoryAddress
  }
}

function getWethAddress(network: string) {
  switch (network) {
    case 'goerliArbitrumEth':
      return '0x163691b2153F4e18F3c3F556426b7f5C74a99FA4'
    case 'goerliArbitrumBtc':
      return '0x603eFB95394c6cf5b6b29B1c813bd1Ee42A07714'
    case 'goerli':
      return '0x163691b2153F4e18F3c3F556426b7f5C74a99FA4'
    case 'arbitrumEth':
      return '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'
    case 'localhost':
      return '0x6466232Bf77e70bEa2535393DC9B2b0d94ea3C22'
    default:
      return undefined
  }
}

function getUsdcAddress(network: string) {
  switch (network) {
    case 'goerliArbitrumEth':
      return '0xE060e715B6D20b899A654687c445ed8BC35f9dFF'
    case 'goerliArbitrumBtc':
      return '0xE060e715B6D20b899A654687c445ed8BC35f9dFF'
    case 'goerli':
      return '0x603eFB95394c6cf5b6b29B1c813bd1Ee42A07714'
    case 'arbitrumEth':
      return '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'
    case 'localhost':
      return '0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c'
    default:
      return undefined
  }
}

function getChainlinkPriceFeed(network: string) {
  switch (network) {
    case 'goerli':
      return constants.AddressZero //'0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e'
    default:
      return constants.AddressZero
  }
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const weth = getWethAddress(network.name)
  const usdc = getUsdcAddress(network.name)

  if (weth === undefined || usdc === undefined) {
    throw new Error('token is not loaded')
  }

  const isMarginZero = parseInt(usdc, 16) < parseInt(weth, 16)

  console.log('isMarginZero', isMarginZero)

  const token0Addr = isMarginZero ? usdc : weth
  const token1Addr = isMarginZero ? weth : usdc

  const InterestCalculator = await ethers.getContract('InterestCalculator', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const UpdatePositionLogic = await ethers.getContract('UpdatePositionLogic', deployer)
  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)
  const PositionLib = await ethers.getContract('PositionLib', deployer)
  const vaultNFT = await ethers.getContract('VaultNFT', deployer)

  const result = await deploy('Controller', {
    from: deployer,
    args: [],
    libraries: {
      UpdatePositionLogic: UpdatePositionLogic.address,
      LiquidationLogic: LiquidationLogic.address,
      PositionUpdater: PositionUpdater.address,
      VaultLib: VaultLib.address,
      PositionLib: PositionLib.address,
      InterestCalculator: InterestCalculator.address,
    },
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            {
              feeTier: 500,
              token0: token0Addr,
              token1: token1Addr,
              isMarginZero,
            },
            getUniswapFactoryAddress(network.name),
            getChainlinkPriceFeed(network.name),
            vaultNFT.address,
          ],
        },
      },
    },
  })

  if (result.newlyDeployed) {
    const controller = await ethers.getContract('Controller', deployer)

    await vaultNFT.init(controller.address)

    await controller.updateIRMParams({
      baseRate: '5000000000000000',
      kinkRate: '750000000000000000',
      slope1: '50000000000000000',
      slope2: '1600000000000000000',
    })
    await controller.updateYearlyPremiumParams(
      {
        baseRate: '10000000000000000',
        kinkRate: '450000000000000000',
        slope1: '60000000000000000',
        slope2: '750000000000000000',
      },
      {
        baseRate: '30625000000000000',
        kinkRate: '450000000000000000',
        slope1: '122500000000000000',
        slope2: '1562500000000000000',
      },
    )

    await controller.setOperator(operatorAddress)
  }
}

export default func
