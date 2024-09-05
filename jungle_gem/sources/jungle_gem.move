module jungle_gem::jungle_gem {
    use std::option;
    use std::signer;
    use std::string;
    use std::string::utf8;
    use std::vector;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::code;
    use aptos_framework::coin;
    use aptos_framework::coin::{MintCapability, BurnCapability};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::function_info;
    use aptos_framework::object;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset,
        FungibleStore, create_store, deposit_with_ref
    };
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use jungle_gem::math::mul_div;
    use jungle_gem::math;

    // The coin names
    const COIN_NAME: vector<u8> = b"Jungle Gem";
    const X_COIN_NAME: vector<u8> = b"X Jungle Gem";
    // The coin symbols
    const COIN_SYMBOL: vector<u8> = b"JGEM";
    const X_COIN_SYMBOL: vector<u8> = b"xJGEM";
    // The coin decimals
    const COIN_DECIMALS: u8 = 6;

    const NULL_ADDRESS: address = @null_address;
    const RESOURCE_ACCOUNT: address = @jungle_gem;
    const DEFAULT_ADMIN: address = @jungle_gem_default_admin;
    const DEV: address = @jungle_gem_dev;

    const FEE_PERCENTAGE: u64 = 25;
    const REMAINING_PERCENTAGE: u64 = 975;
    const TOTAL_SUPPLY: u128 = 500000000000000;

    const TOTAL_WESTING_TIME: u64 = 12 * 30 * 24 * 60 * 60;

    // Error codes
    const ERROR_ONLY_SUPER_ADMIN: u64 = 0;
    const ERROR_USER_ALREADY_ADDED: u64 = 1;
    const ERROR_ONLY_ADMIN: u64 = 2;
    const ERROR_USER_NOT_EXISTS: u64 = 3;
    const ERROR_ALREADY_CLAIMED: u64 = 4;


    struct XToken {}

    struct Capabilities has key { mint_cap: MintCapability<XToken>, burn_cap: BurnCapability<XToken> }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ContractData has key {
        signer_cap: account::SignerCapability,
        super_admin: address,
        admin: vector<address>,
    }

    struct Westing has store {
        total_claimable_assets: u64,
        last_claim_time: u64,
        total_claimed_assets: u64,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct State has key {
        staked_tokens: Object<FungibleStore>,
        total_token_staked: u64,
        total_fee_generated: u64,
        westing_users: SmartTable<address, Westing>,
    }

    fun init_module(admin: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(admin, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);

        let constructor_ref = &object::create_named_object(admin, COIN_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::some(TOTAL_SUPPLY),
            utf8(COIN_NAME),
            utf8(COIN_SYMBOL),
            COIN_DECIMALS,
            utf8(b"http://example.com/favicon.ico"),
            utf8(b"http://example.com"),
        );

        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        move_to(&resource_signer, ManagedFungibleAsset {
            mint_ref,
            burn_ref,
            transfer_ref
        });

        move_to(&resource_signer, ContractData {
            signer_cap,
            super_admin: DEFAULT_ADMIN,
            admin: vector[DEFAULT_ADMIN],
        });

        move_to(&resource_signer, State {
            staked_tokens: create_store(constructor_ref, get_metadata()),
            total_token_staked: 0,
            total_fee_generated: 0,
            westing_users: smart_table::new<address, Westing>(),
        });

        let (burn_cap, freeze_cap, mint_cap) =
            coin::initialize<XToken>(
                &resource_signer,
                utf8(X_COIN_NAME),
                utf8(X_COIN_SYMBOL),
                COIN_DECIMALS,
                true
            );
        coin::destroy_freeze_cap(freeze_cap);

        let caps = Capabilities { mint_cap, burn_cap };
        move_to(&resource_signer, caps);

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"jungle_gem"),
            string::utf8(b"deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"jungle_gem"),
            string::utf8(b"withdraw"),
        );
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );
    }

    public entry fun set_super_admin(sender: &signer, new_admin: address) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let metadata = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //Only super admin can assign new super admin
        assert!(sender_addr == metadata.super_admin, ERROR_ONLY_SUPER_ADMIN);
        metadata.super_admin = new_admin;
    }

    public entry fun set_admin(sender: &signer, new_admin: address) acquires ContractData {
        let sender_addres = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can assign new admin
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);
        vector::push_back(&mut contract_data.admin, new_admin);
    }

    public entry fun remove_admin(sender: &signer, new_admin: address) acquires ContractData {
        let sender_addres = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can remove new admin
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);
        vector::remove_value(&mut contract_data.admin, &new_admin);
    }

    public entry fun upgrade_contract(
        sender: &signer,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let metadata = borrow_global<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can upgrade this contract
        assert!(sender_addr == metadata.super_admin, ERROR_ONLY_SUPER_ADMIN);
        let resource_signer = account::create_signer_with_capability(&metadata.signer_cap);
        code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    public entry fun add_westing_user(
        sender: &signer,
        user: address,
        total_amount: u64
    ) acquires State, ContractData {
        let sender_addr = signer::address_of(sender);
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can upgrade this contract
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        let is_already_added = smart_table::contains(
            &state.westing_users,
            user
        );

        //user already added to westing time
        assert!(!is_already_added, ERROR_USER_ALREADY_ADDED);

        smart_table::add(&mut state.westing_users, user, Westing {
            last_claim_time: timestamp::now_seconds(),
            total_claimable_assets: total_amount,
            total_claimed_assets: 0,
        })
    }

    public entry fun claim_assets(
        user: &signer
    ) acquires State, ManagedFungibleAsset {
        let user_address = signer::address_of(user);
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        let is_exists = smart_table::contains(
            &state.westing_users,
            user_address
        );

        //user not existing in westing
        assert!(is_exists, ERROR_USER_NOT_EXISTS);
        let westing = smart_table::borrow_mut(&mut state.westing_users, user_address);
        assert!(westing.total_claimable_assets > westing.total_claimed_assets, ERROR_ALREADY_CLAIMED);

        let current_time = timestamp::now_seconds();
        let unclaimed_time = current_time - westing.last_claim_time;
        let claimable_asset = (westing.total_claimable_assets / TOTAL_WESTING_TIME) * unclaimed_time;
        if (claimable_asset > westing.total_claimable_assets - westing.total_claimed_assets) {
            claimable_asset = westing.total_claimable_assets - westing.total_claimed_assets
        };
        let asset = get_metadata();
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(user_address, asset);
        let fa = fungible_asset::mint(&managed_fa.mint_ref, claimable_asset);
        fungible_asset::deposit_with_ref(&managed_fa.transfer_ref, to_wallet, fa);

        westing.last_claim_time = current_time;
        westing.total_claimed_assets = westing.total_claimed_assets + claimable_asset;
    }

    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun deposit<T: key>(
        store: Object<T>,
        fa: FungibleAsset,
        transfer_ref: &TransferRef,
    ) acquires State {
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let total_amount = mul_div(fungible_asset::amount(&fa), 1000, REMAINING_PERCENTAGE);
        let fee = mul_div(total_amount, FEE_PERCENTAGE, 1000);
        let fee_fa = fungible_asset::extract(&mut fa, fee);

        state.total_fee_generated = state.total_fee_generated + fee;
        state.total_token_staked = state.total_token_staked + fee;

        fungible_asset::deposit_with_ref(transfer_ref, state.staked_tokens, fee_fa);
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }

    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun withdraw<T: key>(
        store: Object<T>,
        amount: u64,
        transfer_ref: &TransferRef,
    ): FungibleAsset acquires State {
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let fee = mul_div(amount, FEE_PERCENTAGE, 1000);
        let fee_fa = fungible_asset::withdraw_with_ref(transfer_ref, store, fee);

        state.total_fee_generated = state.total_fee_generated + fee;
        state.total_token_staked = state.total_token_staked + fee;

        fungible_asset::deposit_with_ref(transfer_ref, state.staked_tokens, fee_fa);
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount - fee)
    }

    public entry fun stake_token(
        user: &signer,
        amount: u64
    ) acquires State, Capabilities, ManagedFungibleAsset {
        let user_addr = signer::address_of(user);

        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);
        let caps = borrow_global<Capabilities>(@jungle_gem);
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);

        let total_supply = supply();

        let coins;
        let lp_amount;
        if (total_supply != (0 as u128)) {
            let total_supply = total_supply;
            lp_amount = math::mul_div_u128(
                (amount as u128),
                total_supply,
                (state.total_token_staked as u128)
            );
            coins = coin::mint(lp_amount, &caps.mint_cap);
        } else {
            lp_amount = amount;
            coins = coin::mint(lp_amount, &caps.mint_cap);
        };

        check_or_register_coin_store<XToken>(user);

        //withdraw token from user address and hold it in contract
        let asset = get_metadata();
        let transfer_ref = &managed_fa.transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(user_addr, asset);
        let fa = fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount);
        deposit_with_ref(transfer_ref, state.staked_tokens, fa);

        //deposit lp token to user address
        coin::deposit(user_addr, coins);
        state.total_token_staked = state.total_token_staked + amount;
    }

    public entry fun unstake_token(
        user: &signer,
        lp_amount: u64
    ) acquires State, ManagedFungibleAsset, Capabilities {
        let user_addr = signer::address_of(user);

        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);
        let caps = borrow_global<Capabilities>(@jungle_gem);
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);

        let total_supply = supply();

        let amount = math::mul_div_u128(
            (lp_amount as u128),
            (state.total_token_staked as u128),
            total_supply
        );

        //withdraw x token from user address and burn them
        let coins = coin::withdraw<XToken>(user, lp_amount);
        coin::burn(coins, &caps.burn_cap);

        //deposit token amount to user address
        let asset = get_metadata();
        let transfer_ref = &managed_fa.transfer_ref;
        let to_wallet = primary_fungible_store::primary_store(user_addr, asset);
        let fa = fungible_asset::withdraw_with_ref(transfer_ref, state.staked_tokens, amount);
        deposit_with_ref(transfer_ref, to_wallet, fa);

        state.total_token_staked = state.total_token_staked - amount;
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@jungle_gem, COIN_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }


    public entry fun mint(user: &signer, to: address, amount: u64) acquires ManagedFungibleAsset, ContractData {
        let asset = get_metadata();
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fa.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fa.transfer_ref, to_wallet, fa);
    }

    public entry fun transfer(
        from: address,
        to: address,
        amount: u64
    ) acquires ManagedFungibleAsset, State {
        let asset = get_metadata();
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        let transfer_ref = &managed_fa.transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = withdraw(from_wallet, amount, transfer_ref);
        deposit(to_wallet, fa, transfer_ref);
    }

    /// Burn fungible assets as the owner of metadata object.
    public entry fun burn(user: &signer, from: address, amount: u64) acquires ContractData, ManagedFungibleAsset {
        let asset = get_metadata();
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let burn_ref = &managed_fa.burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    fun supply(): u128 {
        option::extract(&mut coin::supply<XToken>())
    }

    #[view]
    public fun get_data(): (u64, u64, u64) acquires State {
        let state = borrow_global<State>(RESOURCE_ACCOUNT);
        (
            fungible_asset::balance(state.staked_tokens),
            state.total_token_staked,
            state.total_fee_generated
        )
    }

    public fun check_or_register_coin_store<CoinType>(sender: &signer) {
        if (!coin::is_account_registered<CoinType>(signer::address_of(sender))) {
            coin::register<CoinType>(sender);
        };
    }
}
