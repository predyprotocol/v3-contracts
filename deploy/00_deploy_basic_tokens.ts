import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  return

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  // Deploy WETH9
  {
    await deploy('MockERC20', { from: deployer, args: ['MockWETH predy', 'mWETH', 18] })
    const weth = await ethers.getContract('MockERC20', deployer)
    console.log(`WETH Deployed at ${weth.address}`)

    const tx = await weth.mint(deployer, '1000000000000000000000000')
    await tx.wait()
  }

  // Deploy WBTC
  {
    await deploy('MockERC20', { from: deployer, args: ['MockWBTC predy', 'mWBTC', 18] })
    const weth = await ethers.getContract('MockERC20', deployer)
    console.log(`WBTC Deployed at ${weth.address}`)

    const tx = await weth.mint(deployer, '1000000000000000000000000')
    await tx.wait()
  }

  // Deploy USDC
  {
    await deploy('MockERC20', { from: deployer, args: ['MockUSDC predy', 'mUSDC', 6] })
    const weth = await ethers.getContract('MockERC20', deployer)
    console.log(`USDC Deployed at ${weth.address}`)

    const tx = await weth.mint(deployer, '10000000000000000')
    await tx.wait()
  }
}

export default func
