import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const ControllerHelper = await ethers.getContract('ControllerHelper', deployer)

  await deploy('Reader', {
    from: deployer,
    args: [ControllerHelper.address],
    log: true,
  })
}

export default func
