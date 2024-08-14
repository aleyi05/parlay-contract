import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("dotenv").config();


const config: HardhatUserConfig = {
  networks: {
    hardhat: {
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: [`${process.env.PRIVATE_KEY}`]
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: [`${process.env.PRIVATE_KEY}`]
    },
  },
  solidity: {
    version: "0.8.20",
    settings: {
      
        optimizer: {
          enabled: true,
          runs: 200,
        },
        viaIR: true,      
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETH_SEPOLIA_API_KEY,
      base: process.env.ETH_BASE_API_KEY,
    },
  }
}

export default config;




