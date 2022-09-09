import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  await deploy('InterestCalculator', { from: deployer, log: true })
  await deploy('PositionCalculator', { from: deployer, log: true })
  await deploy('PositionLib', { from: deployer, log: true })
  await deploy('PositionUpdater', {
    from: deployer,
    log: true,
  })

  const PositionCalculator = await ethers.getContract('PositionCalculator', deployer)

  await deploy('VaultLib', {
    from: deployer,
    log: true,
    libraries: {
      PositionCalculator: PositionCalculator.address,
    },
  })

  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)

  await deploy('LiquidationLogic', {
    from: deployer, log: true,
    libraries: {
      PositionUpdater: PositionUpdater.address,
      PositionCalculator: PositionCalculator.address,
      VaultLib: VaultLib.address
    },

  })

}

export default func
