module jungle_gem::jungle_gem {
    use std::option;
    use std::signer;
    use std::string;
    use std::string::{utf8, String};
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::code;
    use aptos_framework::coin;
    use aptos_framework::coin::{MintCapability, BurnCapability};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::event::{emit_event, EventHandle};
    use aptos_framework::function_info;
    use aptos_framework::object;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset,
        FungibleStore, create_store, deposit_with_ref
    };
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_token_objects::collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use jungle_gem::math::{mul_div, pow};
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
    const ERROR_ALREADY_MINTED: u64 = 5;
    const ERROR_CHEST_NOT_EXISTS: u64 = 6;
    const ERROR_NOT_OWNER: u64 = 7;
    const ERROR_BRONZE_CHEST_REQUIRED: u64 = 8;
    const ERROR_SILVER_CHEST_REQUIRED: u64 = 9;
    const ERROR_DIAMOND_CHEST_REQUIRED: u64 = 10;
    const ERROR_GOLD_CHEST_REQUIRED: u64 = 11;

    // The chest token collection name
    const CHEST_COLLECTION_NAME: vector<u8> = b"Roarlinko Chests";
    // The chest token collection description
    const CHEST_COLLECTION_DESCRIPTION: vector<u8> = b"Chests are earned by playing the Proud Lions: Roarlinko game. Each chest varies in the number of rewards it produces, the higher the tier of the chest, the higher the rewards.";
    // The chest token collection URI
    const CHEST_COLLECTION_URI: vector<u8> = b"https://proudlionsclub.mypinata.cloud/ipfs/QmaMyGHkkkqArpfczz1CKdmevNoqrj2tPXbUrT7fMZedpw";
    // The chest token on chain property type
    const CHEST_TYPE_KEY: vector<u8> = b"ChestType";
    // Chest type
    const SAPPHIRE: vector<u8> = b"SAPPHIRE";
    const DIAMOND: vector<u8> = b"DIAMOND";
    const GOLD: vector<u8> = b"GOLD";
    const SILVER: vector<u8> = b"SILVER";
    const BRONZE: vector<u8> = b"BRONZE";

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
        minting_done: bool,

        // Smart table to store chest of different type
        chests: SmartTable<String, ChestData>,

        //events
        admin_mint_event: EventHandle<AdminMintEvent>,
        admin_burn_event: EventHandle<AdminBurnEvent>,
        add_westing_event: EventHandle<AddWestingEvent>,
        claim_westing_event: EventHandle<ClaimWestingEvent>,
        chest_mint_event: EventHandle<ChestMintEvent>,
        chest_burn_event: EventHandle<ChestBurnEvent>,
        chest_convert_event: EventHandle<ChestConvertEvent>,

    }

    struct Westing has store, drop {
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

        //Events
        stake_token_event: EventHandle<StakeTokenEvent>,
        unstake_token_event: EventHandle<UnstakeTokenEvent>,
    }

    struct ChestData has copy, store, drop {
        name: String,
        description: String,
        token_uri: String,
        start_range: u64,
        end_range: u64,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ChestToken has key {
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    struct AdminMintEvent has drop, store {
        amount: u64,
    }

    struct AdminBurnEvent has drop, store {
        amount: u64,
    }

    struct StakeTokenEvent has drop, store {
        user: address,
        amount: u64,
    }

    struct UnstakeTokenEvent has drop, store {
        user: address,
        amount: u64,
    }

    struct AddWestingEvent has drop, store {
        user: address,
        westing: Westing,
    }

    struct ClaimWestingEvent has drop, store {
        user: address,
        amount: u64,
    }

    struct ChestMintEvent has drop, store {
        owner: address,
        chest_type: String,
    }

    struct ChestBurnEvent has drop, store {
        owner: address,
        chest_type: String,
        chest_reward: u64,
        paw_reward: u64,
    }

    struct ChestConvertEvent has drop, store {
        owner: address,
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
            minting_done: false,
            chests: getChestsData(),
            admin_mint_event: account::new_event_handle<AdminMintEvent>(admin),
            admin_burn_event: account::new_event_handle<AdminBurnEvent>(admin),
            add_westing_event: account::new_event_handle<AddWestingEvent>(admin),
            claim_westing_event: account::new_event_handle<ClaimWestingEvent>(admin),
            chest_mint_event: account::new_event_handle<ChestMintEvent>(admin),
            chest_burn_event: account::new_event_handle<ChestBurnEvent>(admin),
            chest_convert_event: account::new_event_handle<ChestConvertEvent>(admin),
        });

        move_to(&resource_signer, State {
            staked_tokens: create_store(constructor_ref, get_metadata()),
            total_token_staked: 0,
            total_fee_generated: 0,
            westing_users: smart_table::new<address, Westing>(),
            stake_token_event: account::new_event_handle<StakeTokenEvent>(admin),
            unstake_token_event: account::new_event_handle<UnstakeTokenEvent>(admin),
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

        create_chest_collection(&resource_signer);


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
        });

        emit_event<AddWestingEvent>(
            &mut contract_data.add_westing_event,
            AddWestingEvent {
                westing: Westing {
                    last_claim_time: timestamp::now_seconds(),
                    total_claimable_assets: total_amount,
                    total_claimed_assets: 0,
                },
                user
            }
        );
    }

    public entry fun claim_assets(
        user: &signer
    ) acquires State, ManagedFungibleAsset, ContractData {
        let user_address = signer::address_of(user);
        let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

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

        emit_event<ClaimWestingEvent>(
            &mut contract_data.claim_westing_event,
            ClaimWestingEvent {
                user: user_address,
                amount: claimable_asset
            }
        );
    }

    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun deposit<T: key>(
        store: Object<T>,
        fa: FungibleAsset,
        transfer_ref: &TransferRef,
    ) {
        /*let state = borrow_global_mut<State>(RESOURCE_ACCOUNT);
        let total_amount = mul_div(fungible_asset::amount(&fa), 1000, REMAINING_PERCENTAGE);
        let fee = mul_div(total_amount, FEE_PERCENTAGE, 1000);
        let fee_fa = fungible_asset::extract(&mut fa, fee);

        state.total_fee_generated = state.total_fee_generated + fee;
        state.total_token_staked = state.total_token_staked + fee;

        fungible_asset::deposit_with_ref(transfer_ref, state.staked_tokens, fee_fa);*/
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

        emit_event<StakeTokenEvent>(
            &mut state.stake_token_event,
            StakeTokenEvent {
                user: user_addr,
                amount
            }
        );
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

        emit_event<UnstakeTokenEvent>(
            &mut state.unstake_token_event,
            UnstakeTokenEvent {
                user: user_addr,
                amount
            }
        );
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@jungle_gem, COIN_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
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

    public entry fun mint_tokens(user: &signer, to: address, amount: u64) acquires ManagedFungibleAsset, ContractData {
        let asset = get_metadata();
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        //super admin can perform this operation only once
        assert!(!contract_data.minting_done, ERROR_ALREADY_MINTED);

        //only super admin can perform this operation
        assert!(sender_addres == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fa.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fa.transfer_ref, to_wallet, fa);
        contract_data.minting_done = true;

        emit_event<AdminMintEvent>(
            &mut contract_data.admin_mint_event,
            AdminMintEvent {
                amount
            }
        );
    }

    public entry fun burn_tokens(
        user: &signer,
        from: address,
        amount: u64
    ) acquires ContractData, ManagedFungibleAsset {
        let asset = get_metadata();
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);

        //only super admin can perform this operation
        assert!(sender_addres == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        let burn_ref = &managed_fa.burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);

        emit_event<AdminBurnEvent>(
            &mut contract_data.admin_burn_event,
            AdminBurnEvent {
                amount
            }
        );
    }

    fun supply(): u128 {
        option::extract(&mut coin::supply<XToken>())
    }

    public entry fun mint_chest(
        user: &signer,
        chest_type: String,
        receiver_address: address,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        //check if chest type not exists
        assert!(smart_table::contains(&contract_data.chests, chest_type), ERROR_CHEST_NOT_EXISTS);

        let chest_data = smart_table::borrow(&contract_data.chests, chest_type);
        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        mint_chest_internal(resource_signer, chest_data, chest_type, receiver_address);

        emit_event<ChestMintEvent>(
            &mut contract_data.chest_mint_event,
            ChestMintEvent {
                owner: sender_addres,
                chest_type
            }
        );
    }


    #[lint::allow_unsafe_randomness]
    #[randomness]
    entry fun burn_chest(
        user: &signer,
        paw_meter: u64,
        token: Object<ChestToken>
    ) acquires ChestToken, ContractData, ManagedFungibleAsset {
        let sender_addres = signer::address_of(user);
        let asset = get_metadata();
        let managed_fa = borrow_global<ManagedFungibleAsset>(RESOURCE_ACCOUNT);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let owner_address = object::owner(token);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let chest_token = move_from<ChestToken>(object::object_address(&token));
        let ChestToken {
            mutator_ref: _,
            property_mutator_ref: _,
            burn_ref,
        } = chest_token;

        token::burn(burn_ref);
        let chest_type = property_map::read_string(&token, &string::utf8(CHEST_TYPE_KEY));
        let chest_data = smart_table::borrow(
            &contract_data.chests,
            chest_type
        );
        let chest_reward = aptos_framework::randomness::u64_range(
            chest_data.start_range,
            chest_data.end_range
        );
        let paw_reward = mul_div(chest_reward, paw_meter, pow(10, COIN_DECIMALS));
        let reward_amount = (chest_reward + paw_reward) * pow(10, COIN_DECIMALS);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(owner_address, asset);
        let fa = fungible_asset::mint(&managed_fa.mint_ref, reward_amount);
        fungible_asset::deposit_with_ref(&managed_fa.transfer_ref, to_wallet, fa);

        emit_event<ChestBurnEvent>(
            &mut contract_data.chest_burn_event,
            ChestBurnEvent {
                owner: sender_addres,
                chest_type,
                chest_reward,
                paw_reward,
            }
        );
    }


    public entry fun convert_chest(
        admin: &signer,
        owner: address,
        bronze_chest: Object<ChestToken>,
        silver_chest: Object<ChestToken>,
        diamond_chest: Object<ChestToken>,
        gold_chest: Object<ChestToken>
    ) acquires ChestToken, ContractData {
        let admin_address = signer::address_of(admin);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &admin_address), ERROR_ONLY_ADMIN);

        //checks if signer is owner of chest tokens and provide all required type of chests
        assert!(object::is_owner(bronze_chest, owner), ERROR_NOT_OWNER);
        let bronze_type = property_map::read_string(&bronze_chest, &string::utf8(CHEST_TYPE_KEY));
        assert!(bronze_type == string::utf8(BRONZE), ERROR_BRONZE_CHEST_REQUIRED);

        assert!(object::is_owner(silver_chest, owner), ERROR_NOT_OWNER);
        let silver_type = property_map::read_string(&silver_chest, &string::utf8(CHEST_TYPE_KEY));
        assert!(silver_type == string::utf8(SILVER), ERROR_SILVER_CHEST_REQUIRED);

        assert!(object::is_owner(diamond_chest, owner), ERROR_NOT_OWNER);
        let diamond_type = property_map::read_string(&diamond_chest, &string::utf8(CHEST_TYPE_KEY));
        assert!(diamond_type == string::utf8(DIAMOND), ERROR_DIAMOND_CHEST_REQUIRED);

        assert!(object::is_owner(gold_chest, owner), ERROR_NOT_OWNER);
        let gold_type = property_map::read_string(&gold_chest, &string::utf8(CHEST_TYPE_KEY));
        assert!(gold_type == string::utf8(GOLD), ERROR_GOLD_CHEST_REQUIRED);

        let bronze = move_from<ChestToken>(object::object_address(&bronze_chest));
        let ChestToken {
            mutator_ref: _,
            property_mutator_ref: _,
            burn_ref,
        } = bronze;

        token::burn(burn_ref);

        let silver = move_from<ChestToken>(object::object_address(&silver_chest));
        let ChestToken {
            mutator_ref: _,
            property_mutator_ref: _,
            burn_ref,
        } = silver;
        token::burn(burn_ref);

        let gold = move_from<ChestToken>(object::object_address(&gold_chest));
        let ChestToken {
            mutator_ref: _,
            property_mutator_ref: _,
            burn_ref,
        } = gold;
        token::burn(burn_ref);

        let diamond = move_from<ChestToken>(object::object_address(&diamond_chest));
        let ChestToken {
            mutator_ref: _,
            property_mutator_ref: _,
            burn_ref,
        } = diamond;
        token::burn(burn_ref);

        let chest_data = smart_table::borrow(&contract_data.chests, string::utf8(SAPPHIRE));
        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        mint_chest_internal(resource_signer, chest_data, string::utf8(SAPPHIRE), owner);

        emit_event<ChestConvertEvent>(
            &mut contract_data.chest_convert_event,
            ChestConvertEvent {
                owner,
            }
        );
    }


    fun create_chest_collection(user: &signer) {
        let description = string::utf8(CHEST_COLLECTION_DESCRIPTION);
        let name = string::utf8(CHEST_COLLECTION_NAME);
        let uri = string::utf8(CHEST_COLLECTION_URI);

        // Creates the collection with unlimited supply and without establishing any royalty configuration.
        collection::create_unlimited_collection(
            user,
            description,
            name,
            option::none(),
            uri,
        );
    }

    fun mint_chest_internal(
        resource_signer: signer,
        chest_data: &ChestData,
        chest_type: String,
        receiver_address: address)
    {
        // The collection name is used to locate the collection object and to create a new token object.
        let collection = string::utf8(CHEST_COLLECTION_NAME);

        // Creates the chest token, and get the constructor ref of the token. The constructor ref
        // is used to generate the refs of the token.
        let name_str = chest_data.name;
        string::append(&mut name_str, string::utf8(b" #"));
        let constructor_ref = token::create_numbered_token(
            &resource_signer,
            collection,
            chest_data.description,
            name_str,
            string::utf8(b""),
            option::none(),
            chest_data.token_uri,
        );

        // Generates the object signer and the refs.  The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let property_mutator_ref = property_map::generate_mutator_ref(&constructor_ref);

        // Initialize the property map
        let properties = property_map::prepare_input(vector[], vector[], vector[]);
        property_map::init(&constructor_ref, properties);
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(CHEST_TYPE_KEY),
            chest_type
        );
        // Transfers the token to the address
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver_address);

        // Publishes the ChestToken resource with the refs.
        let chest_token = ChestToken {
            mutator_ref,
            burn_ref,
            property_mutator_ref
        };

        move_to(&object_signer, chest_token);
    }

    fun getChestsData(): SmartTable<String, ChestData> {
        let chests = smart_table::new<String, ChestData>();
        smart_table::add(&mut chests, string::utf8(SAPPHIRE), ChestData {
            name: string::utf8(b"Sapphire Chest"),
            description: string::utf8(b"This chest can only be acquired from the Lioness Ritual"),
            token_uri: string::utf8(
                b"https://proudlionsclub.mypinata.cloud/ipfs/QmZUN5YxeuDXNZpZ1shxhLmQovaQbBJyhh4zCQHXyUkVu4/Sapphire%20%282%29.png"
            ),
            start_range: 10000,
            end_range: 10001,
        });
        smart_table::add(&mut chests, string::utf8(DIAMOND), ChestData {
            name: string::utf8(b"Diamond Chest"),
            description: string::utf8(b"This chest pays the highest multiplier of rewards"),
            token_uri: string::utf8(
                b"https://proudlionsclub.mypinata.cloud/ipfs/QmZUN5YxeuDXNZpZ1shxhLmQovaQbBJyhh4zCQHXyUkVu4/Bronze.gif"
            ),
            start_range: 1500,
            end_range: 5000,
        });
        smart_table::add(&mut chests, string::utf8(GOLD), ChestData {
            name: string::utf8(b"Gold Chest"),
            description: string::utf8(b"This chest pays out a 3X multiplier of rewards"),
            token_uri: string::utf8(
                b"https://proudlionsclub.mypinata.cloud/ipfs/QmZUN5YxeuDXNZpZ1shxhLmQovaQbBJyhh4zCQHXyUkVu4/Gold.gif"
            ),
            start_range: 500,
            end_range: 1500,
        });
        smart_table::add(&mut chests, string::utf8(SILVER), ChestData {
            name: string::utf8(b"Silver Chest"),
            description: string::utf8(b"This chest pays out a 2X multiplier of rewards"),
            token_uri: string::utf8(
                b"https://proudlionsclub.mypinata.cloud/ipfs/QmZUN5YxeuDXNZpZ1shxhLmQovaQbBJyhh4zCQHXyUkVu4/Silver.gif"
            ),
            start_range: 150,
            end_range: 500,
        });
        smart_table::add(&mut chests, string::utf8(BRONZE), ChestData {
            name: string::utf8(b"Bronze Chest"),
            description: string::utf8(b"This chest pays out 1X multiplier of rewards"),
            token_uri: string::utf8(
                b"https://proudlionsclub.mypinata.cloud/ipfs/QmZUN5YxeuDXNZpZ1shxhLmQovaQbBJyhh4zCQHXyUkVu4/Bronze.gif"
            ),
            start_range: 50,
            end_range: 150,
        });
        chests
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

    #[view]
    public fun get_chest(
        chest_type: String
    ): (String, String, String, u64, u64) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if chest exists
        let is_already_exists = smart_table::contains(&contract_data.chests, chest_type);
        assert!(is_already_exists, ERROR_CHEST_NOT_EXISTS);

        let chest_data = smart_table::borrow_mut(&mut contract_data.chests, chest_type);
        (
            chest_data.name,
            chest_data.description,
            chest_data.token_uri,
            chest_data.start_range,
            chest_data.end_range,
        )
    }

    #[view]
    public fun get_chest_types(): ( vector<String>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let chests = smart_table::to_simple_map(&mut contract_data.chests);
        let chest_keys = simple_map::keys(&mut chests);

        (
            chest_keys
        )
    }

    public fun check_or_register_coin_store<CoinType>(sender: &signer) {
        if (!coin::is_account_registered<CoinType>(signer::address_of(sender))) {
            coin::register<CoinType>(sender);
        };
    }
}
