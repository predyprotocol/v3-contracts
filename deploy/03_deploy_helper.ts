import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const controller = await ethers.getContract('Controller', deployer)
  await deploy('ControllerHelper', {
    from: deployer,
    args: [controller.address],
    log: true,
  })
}

export default func
