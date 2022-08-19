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

  const LPTMath = await ethers.getContract('LPTMath', deployer)
  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)

  const result = await deploy('Controller', {
    from: deployer,
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
    libraries: {
      LPTMath: LPTMath.address,
      PositionUpdater: PositionUpdater.address,
      VaultLib: VaultLib.address,
    },
    log: true,
  })

  if (result.newlyDeployed) {
    const controller = await ethers.getContract('Controller', deployer)

    await controller.updateIRMParams({
      baseRate: '1000000000000',
      kinkRate: '300000000000000000',
      slope1: '200000000000000000',
      slope2: '500000000000000000',
    })
    await controller.updateDRMParams(
      {
        baseRate: '1000000000000000',
        kinkRate: '300000000000000000',
        slope1: '100000000000000000',
        slope2: '500000000000000000',
      },
      {
        baseRate: '7000000000',
        kinkRate: '300000000000000000',
        slope1: '5000000000',
        slope2: '10000000000',
      },
    )
  }
}

export default func
