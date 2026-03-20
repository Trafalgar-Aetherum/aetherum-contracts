import { ethers, upgrades, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Network:", network.name);

  const balance = await deployer.getBalance();
  console.log("Balance:", ethers.utils.formatEther(balance), "ETH\n");

  // 1. AetherumUSJurisdictionModule
  console.log("Deploying AetherumUSJurisdictionModule...");
  const USJurisdiction = await ethers.getContractFactory("AetherumUSJurisdictionModule");
  const usJurisdiction = await upgrades.deployProxy(USJurisdiction, [], { initializer: "initialize" });
  await usJurisdiction.deployed();
  console.log("  Proxy:", usJurisdiction.address);

  // 2. AetherumCollateralLTVModule
  console.log("Deploying AetherumCollateralLTVModule...");
  const CollateralLTV = await ethers.getContractFactory("AetherumCollateralLTVModule");
  const collateralLTV = await upgrades.deployProxy(CollateralLTV, [], { initializer: "initialize" });
  await collateralLTV.deployed();
  console.log("  Proxy:", collateralLTV.address);

  // 3. AetherumCUMemberModule
  console.log("Deploying AetherumCUMemberModule...");
  const CUMember = await ethers.getContractFactory("AetherumCUMemberModule");
  const cuMember = await upgrades.deployProxy(CUMember, [], { initializer: "initialize" });
  await cuMember.deployed();
  console.log("  Proxy:", cuMember.address);

  // Save deployment addresses
  const deploymentsDir = path.resolve(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deployment = {
    network: network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      AetherumUSJurisdictionModule: usJurisdiction.address,
      AetherumCollateralLTVModule: collateralLTV.address,
      AetherumCUMemberModule: cuMember.address,
    },
  };

  const outPath = path.join(deploymentsDir, "sepolia.json");
  fs.writeFileSync(outPath, JSON.stringify(deployment, null, 2));
  console.log(`\nDeployment saved to ${outPath}`);
  console.log("\nAll modules deployed successfully.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
