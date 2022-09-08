import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  await deploy('InterestCalculator', { from: deployer, log: true })
  await deploy('PositionCalculator', { from: deployer, log: true })
  await deploy('LPTMath', { from: deployer, log: true })
  await deploy('PositionLib', { from: deployer, log: true })

  const PositionCalculator = await ethers.getContract('PositionCalculator', deployer)
  await deploy('VaultLib', {
    from: deployer,
    log: true,
    libraries: {
      PositionCalculator: PositionCalculator.address,
    },
  })

  await deploy('PositionUpdater', {
    from: deployer,
    log: true,
  })
}

export default func
