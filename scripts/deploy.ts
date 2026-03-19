import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // 1. AetherumUSJurisdictionModule
  const USJurisdiction = await ethers.getContractFactory("AetherumUSJurisdictionModule");
  const usJurisdiction = await upgrades.deployProxy(USJurisdiction, [], { initializer: "initialize" });
  await usJurisdiction.deployed();
  console.log("AetherumUSJurisdictionModule:", usJurisdiction.address);

  // 2. AetherumCollateralLTVModule
  const CollateralLTV = await ethers.getContractFactory("AetherumCollateralLTVModule");
  const collateralLTV = await upgrades.deployProxy(CollateralLTV, [], { initializer: "initialize" });
  await collateralLTV.deployed();
  console.log("AetherumCollateralLTVModule:", collateralLTV.address);

  // 3. AetherumCUMemberModule
  const CUMember = await ethers.getContractFactory("AetherumCUMemberModule");
  const cuMember = await upgrades.deployProxy(CUMember, [], { initializer: "initialize" });
  await cuMember.deployed();
  console.log("AetherumCUMemberModule:", cuMember.address);

  console.log("\nAll modules deployed successfully.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
