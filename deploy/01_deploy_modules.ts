import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  await deploy('LPTMath', { from: deployer, log: true })
  await deploy('VaultLib', { from: deployer, log: true })
  await deploy('PositionLib', { from: deployer, log: true })

  const LPTMath = await ethers.getContract('LPTMath', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)

  await deploy('PositionUpdater', {
    from: deployer,
    libraries: {
      LPTMath: LPTMath.address,
      VaultLib: VaultLib.address,
    },
    log: true,
  })
}

export default func
