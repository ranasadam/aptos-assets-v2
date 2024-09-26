# Jungle Run Avatar Contract

This contract is an example for aptos composable nft using aptos digital assets implementation

## Smart Contract Function Documentation

1. Initialize your aptos account
```shell
$ aptos init --network testnet
```
you will get a `.aptos` folder in your current folder.
```yaml
profiles:
  default:
     private_key: "0x0d3a37c1021ae58ee11c145f0370da21222d79405bcc8ec32aa06fbc791e5b3b"
     public_key: "0x0c9cf44d8fdc78cba3ab0974540f169b8f0faf3714d10587be9d55ac00f21adb"
     account: e0a163002dbd1fe2689e94d93aa86c854e823ae5549e645420f2ef361fe63c11 #your_original_account
     rest_url: "https://fullnode.testnet.aptoslabs.com"
     faucet_url: "https://faucet.testnet.aptoslabs.com"
```

2. Get some test APTs
```shell
$ aptos account fund-with-faucet --account YOUR_ACCOUNT --amount 1000000000000
```



3. Create a resource account for `jungle_gem_contract`
```shell
$ aptos move run --function-id '0x1::resource_account::create_resource_account_and_fund' --args 'string:jungle_gem' 'hex:your_original_account' 'u64:10000000'
```

4. Find the address of the resource account
```shell
$ aptos account list --query resources
```

```txt
{
   "0x1::resource_account::Container": {
     "store": {
       "data": [
          {
            "key": "0x7ecfcb185ed80bfc562227324ebf064466e8700b5939b18aaad1af8ed5f1d1a6",
            "value": {
               "account": "0x7ecfcb185ed80bfc562227324ebf064466e8700b5939b18aaad1af8ed5f1d1a6" # this is it, pad zeros to the left if it's shorter than 64 hex chars
          }
        }
      ]
    }
  }
}
```

Or find it on explorer: `https://explorer.aptoslabs.com/account/YOUR_ACCOUNT/resources?network=testnet`

5. Add the resource account in `config.yaml`
```yaml
profiles:
  default:
    private_key: "0x0d3a37c1021ae58ee11c145f0370da21222d79405bcc8ec32aa06fbc791e5b3b"
    public_key: "0x0c9cf44d8fdc78cba3ab0974540f169b8f0faf3714d10587be9d55ac00f21adb"
    account: e0a163002dbd1fe2689e94d93aa86c854e823ae5549e645420f2ef361fe63c11 #your_original_account
    rest_url: "https://fullnode.testnet.aptoslabs.com"
    faucet_url: "https://faucet.testnet.aptoslabs.com"
  jungle_gem:
    private_key: "0x0d3a37c1021ae58ee11c145f0370da21222d79405bcc8ec32aa06fbc791e5b3b"
    public_key: "0x0c9cf44d8fdc78cba3ab0974540f169b8f0faf3714d10587be9d55ac00f21adb"
    account: # add resource account here
    rest_url: "https://fullnode.testnet.aptoslabs.com"
    faucet_url: "https://faucet.testnet.aptoslabs.com"
```

6. Edit `Move.toml`
  ```toml
[package]
name = "jungle_gem"
version = "0.0.1"

# .......
# .......
# .......

[addresses]
jungle_gem = "7ecfcb185ed80bfc562227324ebf064466e8700b5939b18aaad1af8ed5f1d1a6" # replace with the resource account
jungle_gem_default_admin = "e0a163002dbd1fe2689e94d93aa86c854e823ae5549e645420f2ef361fe63c11" # replace with your account
jungle_gem_dev = "e0a163002dbd1fe2689e94d93aa86c854e823ae5549e645420f2ef361fe63c11" # replace with your account
```

7. Compile
```shell
$ aptos move compile
```

8. Publish
```shell
$ aptos move publish --profile jungle_gem
```

9. Use this contract to create and mint composable nft and storing user data online


# Smart Contract Functions Documentation

This document provides detailed descriptions of various functions available in the smart contract, including their parameters and preconditions.

## 1. `add_westing_user`

**Description**:  
Adds a user to a vesting schedule. This defines the amount of assets the user can claim over a specified period. Only the super admin can execute this function.

**Parameters**:
- **`sender: &signer`**: The caller of the transaction. The function verifies that the signer is the super admin.
- **`user: address`**: The address of the user being added to the vesting schedule.
- **`total_amount: u64`**: The total amount of assets claimable by the user over the vesting period.

**Preconditions**:
- Only the super admin can invoke this function.
- The user should not already be part of the vesting schedule.

---

## 2. `claim_assets`

**Description**:  
Allows a user to claim assets they are entitled to based on their vesting schedule. It calculates the claimable amount, mints the assets, and deposits them into the user's wallet.

**Parameters**:
- **`user: &signer`**: The caller of the transaction. The function uses this address to identify the user's vesting schedule.

**Preconditions**:
- The user must be part of the vesting schedule.
- The user must have unclaimed assets available.

---

## 3. `stake_token`

**Description**:  
Allows a user to stake tokens into the contract and receive liquidity pool (LP) tokens in return. The staked tokens are held by the contract, and LP tokens are minted and deposited into the user's wallet.

**Parameters**:
- **`user: &signer`**: The caller of the transaction. The function withdraws tokens from the user's wallet and deposits LP tokens.
- **`amount: u64`**: The amount of tokens the user wants to stake.

---

## 4. `unstake_token`

**Description**:  
Allows a user to unstake LP tokens in exchange for the original staked tokens. The user’s LP tokens are burned, and an equivalent amount of staked tokens is withdrawn and deposited back into the user's wallet.

**Parameters**:
- **`user: &signer`**: The caller of the transaction. Used to identify the user for token withdrawal and LP token burning.
- **`lp_amount: u64`**: The amount of LP tokens to be unstaked.

---

## 5. `mint_tokens`

**Description**:  
Allows the super admin to mint a specified amount of fungible tokens and deposit them into a given address. This function can only be called once.

**Parameters**:
- **`user: &signer`**: The super admin who is minting the tokens.
- **`to: address`**: The address where the minted tokens will be deposited.
- **`amount: u64`**: The amount of tokens to be minted.

**Preconditions**:
- Only the super admin can mint tokens.
- Minting can only be done once.

---

## 6. `burn_tokens`

**Description**:  
Allows the super admin to burn a specified amount of fungible tokens from a given address. The burned tokens are permanently removed from the supply.

**Parameters**:
- **`user: &signer`**: The super admin who is performing the burn.
- **`from: address`**: The address from which tokens are burned.
- **`amount: u64`**: The amount of tokens to be burned.

**Preconditions**:
- Only the super admin can perform the burn.

---

## 7. `mint_chest`

**Description**:  
Allows an admin to mint a chest of a specified type and assign it to a recipient's address. The chest type must exist in the contract's data.

**Parameters**:
- **`user: &signer`**: The admin minting the chest.
- **`chest_type: String`**: The type of chest to be minted.
- **`receiver_address: address`**: The address where the chest will be assigned.

**Preconditions**:
- Only authorized admins can mint chests.
- The specified chest type must exist.

---

## 8. `convert_chest`

**Description**:  
Allows a user to convert four different types of chest tokens (Bronze, Silver, Diamond, and Gold) into a Sapphire chest token. The original chest tokens are burned, and a Sapphire chest is minted.

**Parameters**:
- **`user: &signer`**: The user performing the conversion.
- **`bronze_chest: Object<ChestToken>`**: The Bronze chest token to be converted.
- **`silver_chest: Object<ChestToken>`**: The Silver chest token to be converted.
- **`diamond_chest: Object<ChestToken>`**: The Diamond chest token to be converted.
- **`gold_chest: Object<ChestToken>`**: The Gold chest token to be converted.

**Preconditions**:
- The user must own all four chest tokens (Bronze, Silver, Diamond, and Gold).
- The chest tokens must be of the correct type.

---

## 9. `burn_chest`

**Description**:  
Allows an admin to burn a specified chest token and reward the user with a random amount based on the chest type and a multiplier (paw meter). The reward is minted and deposited into the user's wallet.

**Parameters**:
- **`user: &signer`**: The admin performing the chest burn.
- **`paw_meter: u64`**: A value used to calculate an additional reward.
- **`token: Object<ChestToken>`**: The chest token to be burned.

**Preconditions**:
- Only authorized admins can burn chests.

---

This README provides an overview of the primary functions available within the smart contract, including the necessary parameters and conditions for each function to operate.

