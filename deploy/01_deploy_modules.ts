import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()


  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  // await deploy('PricingModule', { from: deployer, args: [] })
  // await deploy('LPTMathModule', { from: deployer, args: [] })
  // await deploy('VaultLib', { from: deployer, log: true })
}

export default func
