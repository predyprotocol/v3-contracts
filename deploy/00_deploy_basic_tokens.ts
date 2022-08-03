import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)
  return

  const { deploy } = deployments

  // Deploy WETH9
  await deploy('MockERC20', { from: deployer, args: ['MockWETH predy', 'WETH', 18] })
  const weth = await ethers.getContract('MockERC20', deployer)
  console.log(`WETH Deployed at ${weth.address}`)

  const tx = await weth.mint(deployer, '1000000000000000000000000')
  await tx.wait()
}

export default func
