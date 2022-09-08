import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const uniswapPositionManager = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
const uniswapFactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984'
const swapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564'

const wethAddress = '0x6466232Bf77e70bEa2535393DC9B2b0d94ea3C22'
const usdcAddress = '0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const isMarginZero = false

  const InterestCalculator = await ethers.getContract('InterestCalculator', deployer)
  const PositionCalculator = await ethers.getContract('PositionCalculator', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)
  const PositionLib = await ethers.getContract('PositionLib', deployer)

  const result = await deploy('ControllerHelper', {
    from: deployer,
    args: [],
    libraries: {
      LiquidationLogic: LiquidationLogic.address,
      PositionUpdater: PositionUpdater.address,
      VaultLib: VaultLib.address,
      PositionLib: PositionLib.address,
      PositionCalculator: PositionCalculator.address,
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
              token0: wethAddress,
              token1: usdcAddress,
              isMarginZero,
            },
            uniswapPositionManager,
            uniswapFactoryAddress,
            swapRouterAddress,
          ],
        },
      },
    },
  })

  if (result.newlyDeployed) {
    const controller = await ethers.getContract('ControllerHelper', deployer)

    await controller.updateIRMParams({
      baseRate: '1000000000000',
      kinkRate: '300000000000000000',
      slope1: '200000000000000000',
      slope2: '500000000000000000',
    })
    await controller.updateDRMParams(
      {
        baseRate: '1000000000000',
        kinkRate: '300000000000000000',
        slope1: '200000000000000000',
        slope2: '500000000000000000',
      },
      {
        baseRate: '7000000000',
        kinkRate: '300000000000000000',
        slope1: '50000000000',
        slope2: '100000000000',
      },
    )
  }
}

export default func
