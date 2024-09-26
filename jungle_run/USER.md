# User Management Functions Documentation

## 1. create_user
**Description:**  
Creates a new user in the system with the specified details. This function checks if the user already exists and, if not, initializes their data, including wallet addresses, username, and other relevant information.

**Parameters:**
- `user: &signer`: The signer (admin) creating the user.
- `email: String`: The email address of the new user.
- `eth_wallet: address`: The Ethereum wallet address of the new user.
- `aptos_wallet: address`: The Aptos wallet address of the new user.
- `aptos_custodial_wallet: address`: The Aptos custodial wallet address of the new user.
- `username: String`: The username chosen by the new user.

**Preconditions:**
- The caller must be an authorized admin.
- The user must not already exist in the system.

**Errors:**
- `UserAlreadyExists`: Raised if the user with the provided email already exists in the system.

## 2. delete_user
**Description:**  
Removes a user from the system based on their email address. This function ensures that the user exists before deletion and emits an event to log the action.

**Parameters:**
- `user: &signer`: The signer (admin) deleting the user.
- `email: String`: The email address of the user to be deleted.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 3. update_user_score
**Description:**  
Updates the score of a user based on their avatar's name and the new score. The function checks if the user exists, updates their avatar score, and recalculates the total score. An event is emitted to document the update.

**Parameters:**
- `user: &signer`: The signer (admin) updating the user score.
- `email: String`: The email address of the user whose score is being updated.
- `avatar_name: String`: The name of the avatar associated with the score update.
- `new_score: u64`: The new score to be added to the user's total score.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 4. update_user_stake_tokens
**Description:**  
Updates the stake tokens of a specific user. The function checks for the user's existence and modifies their stake tokens accordingly, emitting an event to log the change.

**Parameters:**
- `user: &signer`: The signer (admin) updating the user's stake tokens.
- `email: String`: The email address of the user whose stake tokens are being updated.
- `stake_tokens: u64`: The new number of stake tokens for the user.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 5. add_user_stake_tokens
**Description:**  
Adds a specified amount of stake tokens to a user's existing balance. The function ensures that the user exists in the system before making the addition and emits an event to record the update.

**Parameters:**
- `user: &signer`: The signer (admin) adding stake tokens to the user.
- `email: String`: The email address of the user receiving the stake tokens.
- `stake_tokens: u64`: The amount of stake tokens to add.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 6. add_user_inventory
**Description:**  
Adds an inventory item to a user's account. The function checks if the user exists and if the inventory item is not already present, then adds the item and emits an event to log the addition.

**Parameters:**
- `user: &signer`: The signer (admin) adding an inventory item for the user.
- `email: String`: The email address of the user receiving the inventory item.
- `inventory_item: String`: The inventory item to be added.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.
- `InventoryExists`: Raised if the inventory item already exists for the user.

## 7. update_user_inventory
**Description:**  
Updates an existing inventory item for a user by replacing an old item with a new one. The function checks that both the user and the old inventory item exist before making changes and emits an event to log the update.

**Parameters:**
- `user: &signer`: The signer (admin) updating the user's inventory.
- `email: String`: The email address of the user whose inventory is being updated.
- `old_inventory_item: String`: The inventory item to be replaced.
- `inventory_item: String`: The new inventory item to be added.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.
- `InventoryNotExists`: Raised if the old inventory item does not exist for the user.

## 8. remove_user_inventory
**Description:**  
Removes a specified inventory item from a user's account. The function checks for the existence of the user and the inventory item before proceeding with the removal, emitting an event to log the action.

**Parameters:**
- `user: &signer`: The signer (admin) removing the inventory item for the user.
- `email: String`: The email address of the user whose inventory item is being removed.
- `inventory_item: String`: The inventory item to be removed.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 9. update_user
**Description:**  
Updates various details of a user's account, including wallet addresses, username, and stake tokens. The function verifies the user's existence before applying the changes and emits an event to log the update.

**Parameters:**
- `user: &signer`: The signer (admin) updating the user's information.
- `email: String`: The email address of the user being updated.
- `eth_wallet: address`: The new Ethereum wallet address.
- `aptos_wallet: address`: The new Aptos wallet address.
- `aptos_custodial_wallet: address`: The new Aptos custodial wallet address.
- `username: String`: The new username for the user.
- `stake_tokens: u64`: The updated number of stake tokens.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 10. update_user_basics
**Description:**  
Updates basic user information, including wallet addresses and username. The function checks if the user exists before applying the updates and emits an event to document the change.

**Parameters:**
- `user: &signer`: The signer (admin) updating the user's basic information.
- `email: String`: The email address of the user being updated.
- `eth_wallet: address`: The new Ethereum wallet address.
- `aptos_wallet: address`: The new Aptos wallet address.
- `aptos_custodial_wallet: address`: The new Aptos custodial wallet address.
- `username: String`: The new username for the user.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if a user with the provided email does not exist in the system.

## 11. update_user_actions
**Description:**  
Updates the action limits for all users periodically. This function is called from the backend and checks for each user if their action limits need adjustment based on their cooldown timer.

**Parameters:**
- `user: &signer`: The signer (admin) updating user actions.

**Preconditions:**
- The caller must be an authorized admin.

## 12. consume_user_action
**Description:**  
Allows the admin to consume an action for a specific user. This function checks if the user exists and has remaining actions before consuming one, updating their status accordingly.

**Parameters:**
- `user: &signer`: The signer (admin) consuming the action for the user.
- `email: String`: The email address of the user whose action is being consumed.

**Preconditions:**
- The caller must be an authorized admin.
- The user must exist in the system.

**Errors:**
- `UserNotExists`: Raised if the user with the provided email does not exist in the system.
- `AllActionConsumed`: Raised if the user has no remaining actions.

## 13. add_action_pack
**Description:**  
Allows the super admin to add a new action pack, specifying the details of the pack including the action type and available actions. The function emits an event to log the addition.

**Parameters:**
- `user: &signer`: The signer (super admin) adding the action pack.
- `pack_name: String`: The name of the action pack.
- `action_type: String`: The type of actions included in the pack.
- `actions: u64`: The total number of actions available in the pack.

**Preconditions:**
- The caller must be a super admin.

## 14. buy_action_pack
**Description:**  
Allows a user to purchase an action pack by transferring coins from their account to the super admin's account. The function checks for the user's existence and verifies that the specified action pack is available before proceeding with the purchase.

**Parameters:**
- `user: &signer`: The signer (user) purchasing the action pack.
- `action_type: String`: The type of action pack being purchased.
- `email: String`: The email address of the user making the purchase.

**Preconditions:**
- The caller must be an authorized user.
- The user must exist in the system.
- The action pack specified must be available for purchase.

**Errors:**
- `UserNotExists`: Raised if the user with the provided email does not exist in the system.
- `ActionPackAlreadyExists`: Raised if the action pack specified is not available.

**Emits:**
- `UpdateUserEvent`: Emitted to log the user's updated information after the purchase.  
