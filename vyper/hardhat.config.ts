import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "@nomiclabs/hardhat-vyper";

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  vyper: {
    version: "0.4.0",
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
