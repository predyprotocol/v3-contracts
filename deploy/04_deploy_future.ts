import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

function getUsdcAddress(network: string) {
  switch (network) {
    case 'rinkebyArbitrum':
      return '0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c'
    case 'goerli':
      return '0x603eFB95394c6cf5b6b29B1c813bd1Ee42A07714'
    default:
      return undefined
  }
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const ControllerHelper = await ethers.getContract('ControllerHelper', deployer)
  const Reader = await ethers.getContract('Reader', deployer)
  const VaultNFT = await ethers.getContract('VaultNFT', deployer)

  await deploy('FutureMarket', {
    from: deployer,
    args: [ControllerHelper.address, Reader.address, getUsdcAddress(network.name), VaultNFT.address],
    log: true,
  })
}

export default func
