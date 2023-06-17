import { ethers, hardhatArguments, run } from "hardhat";
import fs from "fs";
import sleep from 'sleep-promise';

const network: string = hardhatArguments.network as string;
const addressOutput = `${__dirname}/networks/${network}/address.json`;
const deployProgress = `${__dirname}/networks/${network}/progress.json`;
const explorers = {
  goerli: "https://goerli.etherscan.io",
  sepolia: "https://sepolia.etherscan.io"
} as {
  [key: string]: string;
};
async function main() {
  const accounts = await ethers.getSigners();
  // const [{ address: governance }] = accounts;
  // let transaction;
  const addresses = {} as {
    [key: string]: string;
  };
  const progress = {} as {
    [key: string]: boolean;
  };
  const explorer: string = explorers[network];
  const [
    AdminControl,
    TrainerManagement,
    FEToken,
    FEBlockchainLearning
  ] = await Promise.all([
    ethers.getContractFactory("AdminControl"),
    ethers.getContractFactory("TrainerManagement"),
    ethers.getContractFactory("FEToken"),
    ethers.getContractFactory("FEBlockchainLearning")
  ]);
  const saveAddresses = async () => {
    await fs.promises.writeFile(addressOutput, JSON.stringify(addresses, null, 2));
    await fs.promises.writeFile(deployProgress, JSON.stringify(progress, null, 2));
  };
  const runWithProgressCheck = async (tag: string, func: Function) => {
    if (progress[tag]) {
      console.log(`Skipping '${tag}'.`);
      return;
    }
    console.log(`Running: ${tag}`);
    try {
      if (func.constructor.name === "AsyncFunction") {
        await func();
      } else {
        func();
      }
    } catch (e) {
      throw e;
    }
    progress[tag] = true;
    await saveAddresses();
  };
  console.log("Prepairing...");
  if (fs.existsSync(addressOutput)) {
    const data = fs.readFileSync(addressOutput);
    Object.assign(addresses, JSON.parse(data.toString()));
  }
  const progressData = fs.readFileSync(deployProgress);
  Object.assign(progress, JSON.parse(progressData.toString()));
  console.log(addresses);
  console.log("Deploying...");
  try {
    let adminControl: any;
    let trainerManagement: any;
    let feToken: any;
    let feBlockchainLearning: any;
    // Deploy AdminControl 
    await runWithProgressCheck("AdminControl", async () => {
      if (!addresses.AdminControl) {
        adminControl = await AdminControl.deploy();
        await adminControl.deployed();
        console.log(`AdminControl address at: ${explorer}/address/${adminControl.address}`);
        addresses.AdminControl = adminControl.address;
      }
      await sleep(30000);
      await run("verify:verify", {
        address: addresses.AdminControl
      }).catch(e => console.log(e.message));
    });
    // Deploy TrainerManager
    await runWithProgressCheck("TrainerManagement", async () => {
      if (!addresses.TrainerManagement) {
        trainerManagement = await TrainerManagement.deploy(addresses.AdminControl);
        await trainerManagement.deployed();
        console.log(`TrainerManagement address at: ${explorer}/address/${trainerManagement.address}`);
        addresses.TrainerManagement = trainerManagement.address;
      }
      await sleep(30000);
      await run("verify:verify", {
        address: addresses.TrainerManagement,
        constructorArguments: [
          addresses.AdminControl
        ]
      }).catch(e => console.log(e.message));
    });
    // Deploy FEToken
    await runWithProgressCheck("FEToken", async () => {
      if (!addresses.FEToken) {
        feToken = await FEToken.deploy(adminControl.address);
        if (feToken && feToken.deployed) {
          await feToken.deployed();
          console.log(`FEToken address at: ${explorer}/address/${feToken.address}`);
          addresses.FEToken = feToken.address;
        }
        else {
          console.log("error");
          return;
        }
      }
      await sleep(30000);
      await run("verify:verify", {
        address: addresses.FEToken,
        constructorArguments: [
          addresses.AdminControl
        ]
      }).catch(e => console.log(e.message));
    });
    // Deploy FEBlockchainLearning
    await runWithProgressCheck("FEBlockchainLearning", async () => {
      if (!addresses.FEBlockchainLearning) {
        feBlockchainLearning = await FEBlockchainLearning.deploy(addresses.AdminControl, addresses.TrainerManagement, addresses.FEToken);
        await feBlockchainLearning.deployed();
        console.log(`FEBlockchainLearning address at: ${explorer}/address/${feBlockchainLearning.address}`);
        addresses.FEBlockchainLearning = feBlockchainLearning.address;
      }
      await sleep(30000);
      await run("verify:verify", {
        address: addresses.FEBlockchainLearning,
        constructorArguments: [
          addresses.AdminControl,
          addresses.TrainerManagement,
          addresses.FEToken
        ]
      }).catch(e => console.log(e.message));
    });
    await sleep(5000);
    // setMinter
    await runWithProgressCheck("AdminControl.setMinter", async () => {
      if (!addresses.FEToken || !addresses.AdminControl || !addresses.FEToken) {
        await adminControl.setMinter(addresses.FEBlockchainLearning);
      }
      else {
        console.log("setMinter Error");
        return;
      }
    });
    await sleep(5000);
    // setBurn
    await runWithProgressCheck("AdminControl.setBurnter", async () => {
      if (!addresses.FEToken || !addresses.AdminControl || !addresses.FEToken) {
        await adminControl.setBurnter(addresses.FEBlockchainLearning);
      }
      else {
        console.log("setBurnter Error");
        return;
      }
    });
  } catch (error) {
    console.log(error);
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
