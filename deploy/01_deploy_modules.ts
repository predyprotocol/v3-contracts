import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  return


  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  //await deploy('PricingModule', { from: deployer, args: [] })
  const predyV3Pool = await ethers.getContract('PredyV3Pool', deployer)
  await deploy('LPTMathModule', { from: deployer, args: [] })
  const lptMathModule = await ethers.getContract('LPTMathModule', deployer)
  await predyV3Pool.setLPTMathModule(lptMathModule.address)

  ///await deploy('VaultLib', { from: deployer, log: true })

}

export default func
