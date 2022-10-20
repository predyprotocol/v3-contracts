import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const uniswapPositionManager = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
const uniswapFactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984'
const swapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564'

function getWethAddress(network: string) {
  switch (network) {
    case 'rinkebyArbitrum':
      return '0x6466232Bf77e70bEa2535393DC9B2b0d94ea3C22'
    case 'goerli':
      return '0x163691b2153F4e18F3c3F556426b7f5C74a99FA4'
    default:
      return undefined
  }
}

function getUsdcAddress(network: string) {
  switch (network) {
    case 'rinkebyArbitrum':
      return '0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c'
    case 'goerli':
      return '0x603eFB95394c6cf5b6b29B1c813bd1Ee42A07714'
    default:
      return undefined
  }
}

function getChainlinkPriceFeed(network: string) {
  switch (network) {
    case 'goerli':
      return '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e'
    default:
      return undefined
  }
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const isMarginZero = false

  const InterestCalculator = await ethers.getContract('InterestCalculator', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)
  const PositionLib = await ethers.getContract('PositionLib', deployer)
  const vaultNFT = await ethers.getContract('VaultNFT', deployer)

  const result = await deploy('Controller', {
    from: deployer,
    args: [],
    libraries: {
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
              token0: getWethAddress(network.name),
              token1: getUsdcAddress(network.name),
              isMarginZero,
            },
            uniswapFactoryAddress,
            swapRouterAddress,
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
      kinkRate: '500000000000000000',
      slope1: '50000000000000000',
      slope2: '600000000000000000',
    })
    await controller.updateYearlyPremiumParams(
      {
        baseRate: '10000000000000000',
        kinkRate: '300000000000000000',
        slope1: '60000000000000000',
        slope2: '750000000000000000',
      },
      {
        baseRate: '40000000000000000',
        kinkRate: '300000000000000000',
        slope1: '160000000000000000',
        slope2: '1000000000000000000',
      },
    )
  }
}

export default func
