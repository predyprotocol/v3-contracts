import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const uniswapPositionManager = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
const uniswapFactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984'
const swapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564'

const usdcAddress = '0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const predyV3Pool = await ethers.getContract('PredyV3Pool', deployer)

  await deploy('ProductVerifier', { from: deployer, args: [predyV3Pool.address], log: true })
  const productVerifier = await ethers.getContract('ProductVerifier', deployer)

  await predyV3Pool.setProductVerifier(productVerifier.address);

  return

  const mockWeth = await ethers.getContract('MockERC20', deployer)
  const isMarginZero = false

  const VaultLib = await ethers.getContract('VaultLib', deployer)


  const result = await deploy('PredyV3Pool', {
    from: deployer,
    args: [mockWeth.address, usdcAddress, isMarginZero, uniswapPositionManager, uniswapFactoryAddress, swapRouterAddress],
    libraries: {
      VaultLib: VaultLib.address,
    },
    log: true
  })

  if (result.newlyDeployed) {
    const predyV3Pool = await ethers.getContract('PredyV3Pool', deployer)
    const pricingModule = await ethers.getContract('PricingModule', deployer)
    const lptMathModule = await ethers.getContract('LPTMathModule', deployer)

    await predyV3Pool.setPricingModule(pricingModule.address)
    await predyV3Pool.setLPTMathModule(lptMathModule.address)

    await deploy('ProductVerifier', { from: deployer, args: [predyV3Pool.address], log: true })
    const productVerifier = await ethers.getContract('ProductVerifier', deployer)

    await predyV3Pool.setProductVerifier(productVerifier.address);
  }
}

export default func
