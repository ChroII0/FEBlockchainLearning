import * as dotenv from 'dotenv';
dotenv.config();
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const {
  ETHERSCAN_API_KEY,
  TESTNET_PRIVATE_KEY,
  INFURA_KEY
} = process.env;


const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
    },
  },
  etherscan: {
    apiKey: {
      // goerli: ETHERSCAN_API_KEY as string,
      sepolia: ETHERSCAN_API_KEY as string,
    }
  },
  networks: {
    goerli: {
      url: `https://goerli.infura.io/v3/${INFURA_KEY}`,
      accounts: [TESTNET_PRIVATE_KEY as string],
      gas: 7000000
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: [TESTNET_PRIVATE_KEY as string],
      gas: 7000000
    }
  },
};

export default config;
