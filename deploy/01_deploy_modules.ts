import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const vaultTokenName = 'pVault-v3-ETH'
const vaultTokenSymbol = 'PVAULT'

function getVaultTokenBaseURI(network: string) {
  switch (network) {
    case 'goerli':
      return 'https://metadata.predy.finance/goerli/'
    case 'arbitrumEth':
      return 'https://metadata.predy.finance/arbitrum/eth/'
    case 'goerliArbitrumEth':
      return 'https://metadata.predy.finance/goerliarbitrum/eth/'
    case 'goerliArbitrumBtc':
      return 'https://metadata.predy.finance/goerliarbitrum/btc/'
    default:
      return ''
  }
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  await deploy('InterestCalculator', { from: deployer, log: true })
  await deploy('PositionLib', { from: deployer, log: true })
  await deploy('PositionUpdater', {
    from: deployer,
    log: true,
  })

  await deploy('VaultLib', {
    from: deployer,
    log: true,
  })

  const PositionUpdater = await ethers.getContract('PositionUpdater', deployer)
  const VaultLib = await ethers.getContract('VaultLib', deployer)

  await deploy('LiquidationLogic', {
    from: deployer,
    log: true,
    libraries: {
      PositionUpdater: PositionUpdater.address,
      VaultLib: VaultLib.address,
    },
  })

  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)

  await deploy('UpdatePositionLogic', {
    from: deployer,
    log: true,
    libraries: {
      PositionUpdater: PositionUpdater.address,
      LiquidationLogic: LiquidationLogic.address,
    },
  })

  const controller = await ethers.getContractOrNull('Controller', deployer)

  if (controller === null) {
    const baseUri = getVaultTokenBaseURI(network.name)
    await deploy('VaultNFT', { from: deployer, args: [vaultTokenName, vaultTokenSymbol, baseUri], log: true })
  }
}

export default func
