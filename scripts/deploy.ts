import { ParlayCoreSimple } from './../typechain-types/contracts/ParlayCoreSimple.sol/ParlayCoreSimple';
import { ethers, network } from "hardhat";
import { ParlayCoreSimple__factory } from "../typechain-types";
// import * as fs from 'fs';
// import ParlayCoreJson from '../artifacts/contracts/ParlayCoreSimple.sol/ParlayCoreSimple.json';


var path = require("path");


async function main() {

  // const networkName = network.name;
  // console.log("Network = ", networkName);

  const provider = new ethers.JsonRpcProvider("https://sepolia.infura.io/v3/14bce4552af443fbb60e05a3f1d71f9b");
  const network = await provider.getNetwork();
  console.log("Network = ", network.name);
  const chainId = await network.chainId;
  console.log("Chain ID = ", chainId);

  const owner = new ethers.Wallet("c1897a9dd6658f632adbae70c1201d8c0dd399c7ff7d1256f1dc405d0998fac9", provider);
  console.log(owner.address);

  const signerAddress = owner.address;
  const initialVirtualEtherBalance = ethers.parseEther("0.5");
  console.log("initial_virtual_eth_balance = ", initialVirtualEtherBalance);
  const initialTokensForUniswapBalance = ethers.parseEther("1000");
  console.log("initial_token_for_uniswapbalance = ", initialTokensForUniswapBalance);
  const initialTokensForBondingCurveBalance = ethers.parseEther("1000");
  console.log("initial_token_for_bc_balance = ", initialTokensForBondingCurveBalance);
  const uniswapV2Router02 = "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008";
  const tradingFeeBasisPoints = 300;
  const createTypeHash = ethers.keccak256(ethers.toUtf8Bytes("CreateTokenRequest(string name,string symbol,uint256 deadline,address creator,uint256 creatorSignatureNonce,uint256 etherFee,uint256 etherBuy,uint256 initialMaxWalletBalance,bool isDevLockup)"));
  console.log('create_type_hash = ', createTypeHash);
  const initCodePairHash = ethers.keccak256(ethers.toUtf8Bytes("InitCodePair"));
  console.log('init_code_pair_hash = ', initCodePairHash);

  const parlayFactory: ParlayCoreSimple__factory = await ethers.getContractFactory("ParlayCoreSimple");
  const parlayContract: ParlayCoreSimple = await parlayFactory.deploy(
    signerAddress,
    initialVirtualEtherBalance,
    initialTokensForUniswapBalance,
    initialTokensForBondingCurveBalance,
    uniswapV2Router02,
    tradingFeeBasisPoints,
    createTypeHash,
    initCodePairHash,
  );
  await parlayContract.waitForDeployment();

  const parlayAddress = await parlayContract.getAddress();
  console.log("Parlay deployed to ", parlayAddress);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
