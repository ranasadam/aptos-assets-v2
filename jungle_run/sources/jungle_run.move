module jungle_run::jungle_run {
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_std::smart_vector;
    use aptos_std::smart_vector::{for_each_mut, SmartVector};
    use aptos_std::string_utils::to_string;
    use aptos_std::type_info::Self;
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_account::transfer_coins;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::code;
    use aptos_framework::coin;
    use aptos_framework::event::{emit_event, EventHandle};
    use aptos_framework::object;
    use aptos_framework::object::{Object, TransferRef};
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_token::token as tokenv1;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token as tokenv2;
    use aptos_token_objects::token::Token as Tokenv2;

    const NULL_ADDRESS: address = @null_address;
    const RESOURCE_ACCOUNT: address = @jungle_run;
    const DEFAULT_ADMIN: address = @jungle_run_default_admin;
    const DEV: address = @jungle_run_dev;

    // Mean 2 percent
    const ROYALITY_NUMERATOR: u64 = 200;
    const ROYALITY_DENOMINATOR: u64 = 10000;

    // Action contants
    const INITIAL_MAX_ACTIONS: u64 = 100;
    const TOTAL_COOL_DOWN_TIME: u64 = 20 * 60;
    //const INITIAL_MAX_ACTIONS: u64 = 5;
    //const TOTAL_COOL_DOWN_TIME: u64 = 1 * 60;

    // Time to earn points = 24 hours
    //const POINT_EARNING_TIME:u64 = 86400;

    // Time to earn points for testing = 5 min
    const POINT_EARNING_TIME: u64 = 300;

    // Error codes
    const ERROR_ONLY_SUPER_ADMIN: u64 = 0;
    const ERROR_ONLY_ADMIN: u64 = 1;
    const ERROR_AVATAR_NOT_EXISTS: u64 = 2;
    const ERROR_AVATAR_PROPERTIES_MISMATCH: u64 = 3;
    const ERROR_AVATAR_ALREADY_CLAIMED: u64 = 4;
    const ERROR_AVATAR_ALREADY_EXISTS: u64 = 5;
    const ERROR_USER_ALREADY_EXISTS: u64 = 6;
    const ERROR_USER_NOT_EXISTS: u64 = 7;
    const ERROR_INVENTRY_EXISTS: u64 = 8;
    const ERROR_NOT_ENOUGH_SCORE: u64 = 9;
    const ERROR_DIVIDE_BY_ZERO: u64 = 10;
    const ERROR_NOT_OWNER: u64 = 11;
    const ERROR_TOKEN_NOT_CLAIMABLE: u64 = 12;
    const ERROR_WRONG_COLLECTION: u64 = 14;
    const ERROR_NO_TRANSFER_REF: u64 = 15;
    const ERROR_INVENTORY_NOT_EXISTS: u64 = 16;
    const ERROR_ALL_ACTION_CONSUMED: u64 = 17;
    const ERROR_ACTION_PACK_ALREADY_EXISTS: u64 = 18;
    const ERROR_NFT_NOT_STAKED: u64 = 19;
    const ERROR_COLLECTION_NOT_EXIST: u64 = 20;
    const ERROR_ACTION_PACK_NOT_EXISTS: u64 = 21;
    const ERROR_POOL_EXIST: u64 = 22;
    const ERROR_COIN_NOT_EXIST: u64 = 23;
    const ERROR_POOL_NOT_EXIST: u64 = 24;
    const ERROR_NFT_NOT_ENOUGH_AMOUNT: u64 = 25;


    // The avatar token collection name
    const COLLECTION_NAME: vector<u8> = b"Jungle Run Avatars";
    // The avatar token collection description
    const COLLECTION_DESCRIPTION: vector<u8> = b"A 3D collection of unlockable and playable characters within Jungle Run, these characters are tradable unless soul-bound, they are dynamic and can be customized and upgraded as users level up.";
    // The avatar token collection URI
    const COLLECTION_URI: vector<u8> = b"Avatar Collection URI";

    struct ContractData has key {
        signer_cap: account::SignerCapability,
        super_admin: address,
        admin: vector<address>,

        //all royality will be calculating here
        royality: coin::Coin<AptosCoin>,

        // Store address that have already claimed free avatars
        claimed_addresses: vector<address>,
        claimed_soul_bound_addresses: vector<address>,

        // Store address of whitelist collection or creator in case of v1 nft and extra moves to get when stake nft
        whitelist_data: SmartTable<address, WhitelistData>,

        // vectors to store staked nft information
        staked_nfts: SmartVector<StakedNFT>,

        // vectors to store staked v1 nft information
        staked_v1_nfts: SmartVector<StakedV1NFT>,

        // Smart table to store avatar of different type
        avatars: SmartTable<String, AvatarData>,

        // Smart table to store users
        users: SmartTable<String, UserData>,

        // Smart table to owner of special nft that will get royality
        royality_owners: SmartTable<address, u64>,

        // Smart table to store action packs
        action_packs: SmartTable<String, ActionData>,

        //events to emit on every action
        user_created_event: EventHandle<CreateUserEvent>,
        user_updated_event: EventHandle<UpdateUserEvent>,
        user_deleted_event: EventHandle<DeleteUserEvent>,
        token_property_event: EventHandle<TokenPropertyEvent>,
        add_whitelist_collection_event: EventHandle<AddWhitelistCollectionEvent>,
        update_whitelist_collection_event: EventHandle<UpdateWhitelistCollectionEvent>,
        remove_whitelist_collection_event: EventHandle<RemoveWhitelistCollectionEvent>,
        add_action_pack_event: EventHandle<AddActionPackEvent>,
        delete_action_pack_event: EventHandle<DeleteActionPackEvent>,
        buy_action_pack_event: EventHandle<BuyActionPackEvent>,
        stake_nft_event: EventHandle<StakeNFTEvent>,
        unstake_nft_event: EventHandle<UnstakeNFTEvent>,
        stake_v1_nft_event: EventHandle<StakeV1NFTEvent>,
        unstake_v1_nft_event: EventHandle<UnstakeV1NFTEvent>,
        create_pool_event: EventHandle<CreatePoolEvent>,
        update_supply_event: EventHandle<UpdateSupplyEvent>,
        update_reward_event: EventHandle<UpdateRewardEvent>,
        send_reward_event: EventHandle<SendRewardEvent>,
        withdraw_supply_event: EventHandle<WithdrawSupplyEvent>,

    }

    struct PoolInfo<phantom CoinType> has key {
        supply: coin::Coin<CoinType>,
        image_url: String,
        reward_amount: u64,
    }

    struct WhitelistData has copy, store, drop {
        address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64,
    }

    struct LeaderBoardData has copy, store, drop {
        staker: address,
        points_earned: u64,
    }

    struct StakedNFT has copy, store, drop {
        collection_address: address,
        token_id: address,
        staker: address,
        reward_moves: u64,
        staking_time: u64,
        points_per_day: u64,
        points_earned: u64,
    }

    struct StakedV1NFT has copy, store, drop {
        staker: address,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        reward_moves: u64,
        amount: u64,
        staking_time: u64,
        points_per_day: u64,
        points_earned: u64,
    }

    struct UserData has copy, store, drop {
        eth_wallet: address,
        aptos_wallet: address,
        aptos_custodial_wallet: address,
        username: String,
        email: String,
        stake_tokens: u64,
        score: u64,
        max_actions: u64,
        remaining_actions: u64,
        last_cool_down_time: u64,
        cool_down_timer: u64,
        avatar_score: vector<AvatarScore>,
        inventory: vector<String>,
        total_points_earned: u64,
        v1_points: vector<StakingReward>,
        v2_points: vector<StakingReward>,
    }

    struct StakingReward has copy, store, drop {
        address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64,
        points_earned: u64,
    }

    struct AvatarScore has copy, store, drop {
        name: String,
        score: u64,
    }

    struct AvatarData has copy, store, drop {
        name: String,
        description: String,
        type: String,
        price: u64,
        token_uri: String,
        properties: vector<AvatarProperties>,
        royality_token_id: address,
        position: u64,
        is_soul_bound: bool,
        collection_address: address
    }

    struct AvatarProperties has copy, store, drop {
        key: String,
        value: String,
    }

    struct ActionData has copy, store, drop {
        name: String,
        price: u64,
        action_received: u64,
    }

    //Events
    struct CreateUserEvent has drop, store {
        email: String,
    }

    struct DeleteUserEvent has drop, store {
        email: String,
    }

    struct UpdateUserEvent has drop, store {
        user_data: UserData,
    }

    struct TokenPropertyEvent has drop, store {
        token_address: address,
        key: String,
        value: String,
    }

    struct AddWhitelistCollectionEvent has drop, store {
        address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64,
    }

    struct UpdateWhitelistCollectionEvent has drop, store {
        address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64,
    }

    struct RemoveWhitelistCollectionEvent has drop, store {
        address: address,
    }

    struct AddActionPackEvent has drop, store {
        action_data: ActionData,
        action_type: String,
    }

    struct DeleteActionPackEvent has drop, store {
        action_type: String,
    }

    struct BuyActionPackEvent has drop, store {
        action_data: ActionData,
        user_email: String,
    }

    struct StakeNFTEvent has drop, store {
        collection_address: address,
        token_id: address,
        staker: address,
        reward_moves: u64,
        staking_time: u64,
        points_per_day: u64,
    }

    struct UnstakeNFTEvent has drop, store {
        token_id: address,
        staker: address,
    }

    struct StakeV1NFTEvent has drop, store {
        staker: address,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        reward_moves: u64,
        amount: u64,
        staking_time: u64,
        points_per_day: u64,
    }

    struct UnstakeV1NFTEvent has drop, store {
        staker: address,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
    }

    struct CreatePoolEvent has drop, store {
        coin_address: address,
        reward_amount: u64,
        image_url: String,
        supply: u64
    }

    struct UpdateSupplyEvent has drop, store {
        coin_address: address,
        supply: u64
    }

    struct UpdateRewardEvent has drop, store {
        coin_address: address,
        reward_amount: u64
    }

    struct SendRewardEvent has drop, store {
        coin_address: address,
        receiver_address: address,
        reward_amount: u64
    }

    struct WithdrawSupplyEvent has drop, store {
        coin_address: address,
        receiver_address: address,
        withdraw_amount: u64,
    }


    // NFT related structures
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AvatarToken has key {
        head_gear: Option<Object<HeadGear>>,
        weapon_equipped: Option<Object<Weapon>>,
        inventory: Option<Object<Inventry>>,
        armor: Option<Object<Armor>>,
        shoes: Option<Object<Shoes>>,

        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct HeadGear has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Weapon has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }


    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Inventry has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Armor has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Shoes has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);


        move_to(&resource_signer, ContractData {
            signer_cap,
            super_admin: DEFAULT_ADMIN,
            admin: vector[DEFAULT_ADMIN],
            claimed_addresses: vector::empty<address>(),
            claimed_soul_bound_addresses: vector::empty<address>(),
            whitelist_data: smart_table::new<address, WhitelistData>(),
            staked_nfts: smart_vector::empty<StakedNFT>(),
            staked_v1_nfts: smart_vector::empty<StakedV1NFT>(),
            avatars: smart_table::new<String, AvatarData>(),
            users: smart_table::new<String, UserData>(),
            action_packs: smart_table::new<String, ActionData>(),
            royality: coin::zero<AptosCoin>(),
            royality_owners: smart_table::new<address, u64>(),
            //events
            user_created_event: account::new_event_handle<CreateUserEvent>(sender),
            user_updated_event: account::new_event_handle<UpdateUserEvent>(sender),
            user_deleted_event: account::new_event_handle<DeleteUserEvent>(sender),
            token_property_event: account::new_event_handle<TokenPropertyEvent>(sender),
            add_whitelist_collection_event: account::new_event_handle<AddWhitelistCollectionEvent>(sender),
            update_whitelist_collection_event: account::new_event_handle<UpdateWhitelistCollectionEvent>(sender),
            remove_whitelist_collection_event: account::new_event_handle<RemoveWhitelistCollectionEvent>(sender),
            add_action_pack_event: account::new_event_handle<AddActionPackEvent>(sender),
            delete_action_pack_event: account::new_event_handle<DeleteActionPackEvent>(sender),
            buy_action_pack_event: account::new_event_handle<BuyActionPackEvent>(sender),
            stake_nft_event: account::new_event_handle<StakeNFTEvent>(sender),
            stake_v1_nft_event: account::new_event_handle<StakeV1NFTEvent>(sender),
            unstake_nft_event: account::new_event_handle<UnstakeNFTEvent>(sender),
            unstake_v1_nft_event: account::new_event_handle<UnstakeV1NFTEvent>(sender),
            create_pool_event: account::new_event_handle<CreatePoolEvent>(sender),
            update_supply_event: account::new_event_handle<UpdateSupplyEvent>(sender),
            update_reward_event: account::new_event_handle<UpdateRewardEvent>(sender),
            send_reward_event: account::new_event_handle<SendRewardEvent>(sender),
            withdraw_supply_event: account::new_event_handle<WithdrawSupplyEvent>(sender),
        });
        create_avatar_collection(&resource_signer);
    }

    public entry fun set_super_admin(sender: &signer, new_admin: address) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let metadata = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //Only super admin can assign new super admin
        assert!(sender_addr == metadata.super_admin, ERROR_ONLY_SUPER_ADMIN);
        metadata.super_admin = new_admin;
    }

    // will receive collection address for v2 or creator address in case of v1
    public entry fun add_whitelist_data(
        sender: &signer,
        collection_creator_address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can white list collection/creator
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);
        smart_table::add(&mut contract_data.whitelist_data, collection_creator_address, WhitelistData {
            address: collection_creator_address,
            extra_moves_on_staking,
            points_per_day
        });

        emit_event<AddWhitelistCollectionEvent>(
            &mut contract_data.add_whitelist_collection_event,
            AddWhitelistCollectionEvent {
                address: collection_creator_address,
                extra_moves_on_staking,
                points_per_day
            }
        );
    }

    // will receive collection address for v2 or creator address in case of v1
    public entry fun remove_whitelist_data(
        sender: &signer,
        collection_creator_address: address
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can remove whitelist collection/creator
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);
        smart_table::remove(&mut contract_data.whitelist_data, collection_creator_address);

        emit_event<RemoveWhitelistCollectionEvent>(
            &mut contract_data.remove_whitelist_collection_event,
            RemoveWhitelistCollectionEvent {
                address: collection_creator_address,
            }
        );
    }

    // will receive collection address for v2 or creator address in case of v1
    public entry fun update_whitelist_data(
        sender: &signer,
        collection_creator_address: address,
        extra_moves_on_staking: u64,
        points_per_day: u64
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can update whitelist collection/creator
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if whitelist collection exists
        assert!(
            smart_table::contains(&contract_data.whitelist_data, collection_creator_address),
            ERROR_COLLECTION_NOT_EXIST
        );

        smart_table::remove(&mut contract_data.whitelist_data, collection_creator_address);
        smart_table::add(
            &mut contract_data.whitelist_data,
            collection_creator_address,
            WhitelistData {
                address: collection_creator_address,
                extra_moves_on_staking,
                points_per_day
            }
        );

        emit_event<UpdateWhitelistCollectionEvent>(
            &mut contract_data.update_whitelist_collection_event,
            UpdateWhitelistCollectionEvent {
                address: collection_creator_address,
                extra_moves_on_staking,
                points_per_day,
            }
        );
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

    public entry fun add_avatar(
        sender: &signer,
        avatar_name: String,
        avatar_description: String,
        avatar_type: String,
        avatar_price: u64,
        avatar_token_uri: String,
        avatar_properties_keys: vector<String>,
        avatar_properties_values: vector<String>,
        collection_address: address,
        royality_token_id: address,
        is_soul_bound: bool
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can call this method
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(!smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_ALREADY_EXISTS);

        //keys and values must have same length
        assert!(
            vector::length(&avatar_properties_keys) == vector::length(&avatar_properties_values),
            ERROR_AVATAR_PROPERTIES_MISMATCH
        );

        let data = AvatarData {
            name: avatar_name,
            description: avatar_description,
            type: avatar_type,
            price: avatar_price,
            token_uri: avatar_token_uri,
            properties: vector::empty(),
            royality_token_id,
            position: 1,
            is_soul_bound,
            collection_address
        };
        let i = 0;
        while (i < vector::length(&avatar_properties_keys)) {
            vector::push_back(&mut data.properties, AvatarProperties {
                key: *vector::borrow(&avatar_properties_keys, i),
                value: *vector::borrow(&avatar_properties_values, i),
            });
            i = i + 1
        };
        smart_table::add(&mut contract_data.avatars, avatar_type, data);
    }

    public entry fun update_avatar_price(
        sender: &signer,
        type: String,
        price: u64,
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can call this method
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(smart_table::contains(&contract_data.avatars, type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, type);
        avatar_data.price = price;
    }

    public entry fun toggle_avatar_soul_bound(
        sender: &signer,
        type: String,
        is_soul_bound: bool,
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can call this method
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(smart_table::contains(&contract_data.avatars, type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, type);
        avatar_data.is_soul_bound = is_soul_bound;
    }

    public entry fun update_avatar_uri(
        sender: &signer,
        type: String,
        token_uri: String,
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can call this method
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(smart_table::contains(&contract_data.avatars, type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, type);
        avatar_data.token_uri = token_uri;
    }

    //This method will remove all old properties of avatar and add new properties
    public entry fun update_avatar_properties(
        sender: &signer,
        type: String,
        properties_keys: vector<String>,
        properties_values: vector<String>
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can call this method
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(smart_table::contains(&contract_data.avatars, type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, type);
        avatar_data.properties = vector::empty<AvatarProperties>();
        let i = 0;
        while (i < vector::length(&properties_keys)) {
            vector::push_back(&mut avatar_data.properties, AvatarProperties {
                key: *vector::borrow(&properties_keys, i),
                value: *vector::borrow(&properties_values, i),
            });
            i = i + 1
        };
    }

    /// Mints a free soul-bound avatar to the user's address.
    ///
    /// # Description
    /// This function allows a user to claim a free soul-bound token of the specified avatar type.
    /// The token is tied to the user's address and cannot be transferred.
    ///
    /// # Parameters
    /// - `user`: A reference to the signer initiating the transaction. This is the recipient of the soul-bound avatar.
    /// - `avatar_type`: A `String` specifying the type of avatar the user wants to mint.
    ///
    /// # Behavior
    /// - Verifies that the provided `avatar_type` exists in the contract.
    /// - Ensures that the user's address has not already claimed a free avatar.
    /// - Updates the `claimed_soul_bound_addresses` list to include the user's address.
    /// - Mints a new soul-bound token of the specified `avatar_type` to the user's address.
    ///
    /// # Requirements
    /// - The `avatar_type` must exist in the `avatars` smart table within the `ContractData`.
    /// - The user's address must not have already claimed a soul-bound avatar.
    ///
    /// # Errors
    /// - `ERROR_AVATAR_NOT_EXISTS`: Raised if the specified `avatar_type` does not exist.
    /// - `ERROR_AVATAR_ALREADY_CLAIMED`: Raised if the user has already claimed a soul-bound avatar.
    ///
    /// # Example
    /// ```
    /// // Assuming `user_signer` is the user:
    /// mint_free_soul_bound_avatar(&user_signer, "LOIN");
    /// ```
    public entry fun mint_free_soul_bound_avatar(
        user: &signer,
        avatar_type: String,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        // This will check if this address have already claimed free avatar
        assert!(
            !vector::contains(&mut contract_data.claimed_soul_bound_addresses, &sender_addres),
            ERROR_AVATAR_ALREADY_CLAIMED
        );

        vector::push_back(&mut contract_data.claimed_soul_bound_addresses, sender_addres);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, avatar_type);

        mint_token(contract_data, avatar_type, sender_addres, avatar_data.is_soul_bound);
    }

    /// Mints a free avatar to the specified receiver address.
    ///
    /// # Description
    /// This function allows an admin to mint a free avatar of a specified type to a given receiver's address.
    /// The admin can also define whether the avatar should be soul-bound (non-transferable).
    ///
    /// # Parameters
    /// - `admin`: A reference to the signer who is an authorized admin. Only an admin can call this function.
    /// - `avatar_type`: A `String` specifying the type of avatar to mint.
    /// - `receiver_address`: The `address` of the recipient who will receive the minted avatar.
    /// - `is_soul_bound`: A `bool` indicating whether the avatar is soul-bound (`true`) or transferable (`false`).
    ///
    /// # Behavior
    /// - Verifies that the caller (`admin`) is authorized and exists in the list of admins.
    /// - Ensures that the provided `avatar_type` exists in the `ContractData`.
    /// - Mints a new avatar of the specified type to the `receiver_address` with the provided soul-bound property.
    ///
    /// # Requirements
    /// - The caller (`admin`) must have admin privileges.
    /// - The `avatar_type` must exist in the `avatars` smart table within the `ContractData`.
    ///
    /// # Errors
    /// - `ERROR_ONLY_ADMIN`: Raised if the caller is not an admin.
    /// - `ERROR_AVATAR_NOT_EXISTS`: Raised if the specified `avatar_type` does not exist.
    ///
    /// # Example
    /// ```
    /// // Assuming `admin_signer` is the admin:
    /// admin_mint_free_avatar(&admin_signer, "LOIN", recipient_address, true);
    /// ```
    public entry fun admin_mint_free_avatar(
        admin: &signer,
        avatar_type: String,
        receiver_address: address,
        is_soul_bound: bool,
    ) acquires ContractData {
        let sender_addres = signer::address_of(admin);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        mint_token(contract_data, avatar_type, receiver_address, is_soul_bound);
    }

    /// Mints a free avatar to the user's address.
    ///
    /// # Description
    /// This function allows a user to claim a free 2D avatar of a specified type. The avatar is soul-bound (non-transferable)
    /// and tied to the user's address. The user must own a token from a specific whitelisted collection to claim the avatar.
    ///
    /// # Parameters
    /// - `user`: A reference to the signer initiating the transaction. This is the recipient of the 2D avatar.
    /// - `avatar_type`: A `String` specifying the type of 2D avatar the user wants to mint.
    /// - `token_id`: An `address` representing the token the user owns, which will be verified as part of the whitelisted collection.
    ///
    /// # Behavior
    /// - Verifies that the specified `avatar_type` exists in the contract.
    /// - Retrieves the associated token and verifies it belongs to a whitelisted collection.
    /// - Ensures the caller (`user`) is the owner of the token.
    /// - Checks that the caller's address has not already claimed a free 2D avatar.
    /// - Updates the list of claimed addresses and mints a new soul-bound avatar of the specified type to the user's address.
    ///
    /// # Requirements
    /// - The specified `avatar_type` must exist in the `avatars` within the contract.
    /// - The token identified by `token_id` must belong to a whitelisted collection.
    /// - The signer (`user`) must be the owner of the token.
    /// - The signer must not have already claimed a free avatar.
    ///
    /// # Errors
    /// - `ERROR_AVATAR_NOT_EXISTS`: Raised if the specified `avatar_type` does not exist.
    /// - `ERROR_WRONG_COLLECTION`: Raised if the token does not belong to the whitelisted collection.
    /// - `ERROR_NOT_OWNER`: Raised if the signer is not the owner of the token.
    /// - `ERROR_AVATAR_ALREADY_CLAIMED`: Raised if the signer has already claimed a free avatar.
    ///
    /// # Example
    /// ```
    /// // Assuming `user_signer` is the user:
    /// mint_free_2D_avatar(&user_signer, "LION", token_address);
    /// ```
    public entry fun mint_free_2D_avatar(
        user: &signer,
        avatar_type: String,
        token_id: address,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let token = object::address_to_object<Tokenv2>(token_id);
        let collection = tokenv2::collection_object(token);
        let collection_address = object::object_address<Collection>(&collection);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow(&contract_data.avatars, avatar_type);

        //check if token belongs to whitelist collection
        assert!(avatar_data.collection_address == collection_address, ERROR_WRONG_COLLECTION);

        //check if signer is owner of token
        assert!(object::is_owner(token, sender_addres), ERROR_NOT_OWNER);

        // This will check if this address have already claimed free avatar
        assert!(
            !vector::contains(&mut contract_data.claimed_addresses, &sender_addres),
            ERROR_AVATAR_ALREADY_CLAIMED
        );

        vector::push_back(&mut contract_data.claimed_addresses, sender_addres);

        mint_token(contract_data, avatar_type, sender_addres, true);
    }

    // Mints token. This function mints a new token when user pay it via nft pay and transfers it to the receiver address.
    public entry fun mint_nft_pay_avatar(
        user: &signer,
        avatar_type: String,
        receiver_address: address,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = *smart_table::borrow(&mut contract_data.avatars, avatar_type);

        //calculating royality
        calculate_royality(user, contract_data, avatar_data);
        //minting token
        mint_token(contract_data, avatar_type, receiver_address, false);
    }

    // Mints paid token. This function mints a new token to user wallet and deduct avatar price from user wallet
    public entry fun mint_paid_avatar(
        user: &signer,
        avatar_type: String,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = *smart_table::borrow(&mut contract_data.avatars, avatar_type);

        //calculating royality
        calculate_royality(user, contract_data, avatar_data);

        mint_token(contract_data, avatar_type, sender_addres, false);
    }

    // Claim royality for a beta lion only owner of that nft can be able to claim royality
    public entry fun claim_royality(
        user: &signer,
        token_id: address,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let token = object::address_to_object<Tokenv2>(token_id);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user is owner of proud lion nft so he can claim
        assert!(object::is_owner(token, sender_addres), ERROR_NOT_OWNER);
        //check if some royality is available for this token
        assert!(smart_table::contains(&contract_data.royality_owners, token_id), ERROR_TOKEN_NOT_CLAIMABLE);

        let royality_amount = *smart_table::borrow(&contract_data.royality_owners, token_id);
        transfer_out<AptosCoin>(&mut contract_data.royality, user, royality_amount);
        smart_table::remove(&mut contract_data.royality_owners, token_id);
    }


    // Update property of avatar tokens that are already minted on chain
    public entry fun update_token_property(
        user: &signer,
        token: Object<AvatarToken>,
        key: String,
        value: String,
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);
        // Gets `property_mutator_ref` to update the property in the property map.
        let property_mutator_ref = &avatar_token.property_mutator_ref;

        // Updates the property of avatar in the property map.
        property_map::update_typed(property_mutator_ref, &key, value);

        emit_event<TokenPropertyEvent>(
            &mut contract_data.token_property_event,
            TokenPropertyEvent {
                token_address,
                key,
                value,
            }
        );
    }

    // add property of avatar tokens that are already minted on chain
    public entry fun add_token_property(
        user: &signer,
        token: Object<AvatarToken>,
        key: String,
        value: String,
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);
        // Gets `property_mutator_ref` to add the property in the property map.
        let property_mutator_ref = &avatar_token.property_mutator_ref;

        // add new property of avatar in the property map.
        property_map::add_typed(property_mutator_ref, key, value);
        emit_event<TokenPropertyEvent>(
            &mut contract_data.token_property_event,
            TokenPropertyEvent {
                token_address,
                key,
                value,
            }
        );
    }

    // this function will toggle soulbound functionality of token
    public entry fun toggle_soul_bound(
        user: &signer,
        token: Object<AvatarToken>,
        is_soul_bound: bool,
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);
        assert!(option::is_some(&avatar_token.transfer_ref), ERROR_NO_TRANSFER_REF);
        let avatar_transfer_ref = option::borrow(&avatar_token.transfer_ref);
        if (is_soul_bound) {
            object::disable_ungated_transfer(avatar_transfer_ref);
        }else {
            object::enable_ungated_transfer(avatar_transfer_ref);
        }
    }

    // update avatar token uri on chain
    public entry fun update_token_uri(
        user: &signer,
        token: Object<AvatarToken>,
        new_token_uri: String
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);

        tokenv2::set_uri(&avatar_token.mutator_ref, new_token_uri);
    }

    // update avatar token name on chain
    public entry fun update_token_name(
        user: &signer,
        token: Object<AvatarToken>,
        new_name: String
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);

        tokenv2::set_name(&avatar_token.mutator_ref, new_name);
    }

    // update avatar token description on chain
    public entry fun update_token_description(
        user: &signer,
        token: Object<AvatarToken>,
        new_decs: String
    ) acquires AvatarToken, ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);

        let token_address = object::object_address(&token);
        let avatar_token = borrow_global<AvatarToken>(token_address);

        tokenv2::set_description(&avatar_token.mutator_ref, new_decs);
    }


    public entry fun create_user(
        user: &signer,
        email: String,
        eth_wallet: address,
        aptos_wallet: address,
        aptos_custodial_wallet: address,
        username: String,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user already exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(!is_already_exists, ERROR_USER_ALREADY_EXISTS);

        let user_data = UserData {
            email,
            eth_wallet,
            aptos_wallet,
            aptos_custodial_wallet,
            username,
            stake_tokens: 0,
            score: 0,
            remaining_actions: INITIAL_MAX_ACTIONS,
            max_actions: INITIAL_MAX_ACTIONS,
            last_cool_down_time: 0,
            cool_down_timer: TOTAL_COOL_DOWN_TIME,
            avatar_score: vector::empty(),
            inventory: vector::empty(),
            total_points_earned: 0,
            v1_points: vector::empty(),
            v2_points: vector::empty(),
        };

        smart_table::add(&mut contract_data.users, email, user_data);

        emit_event<CreateUserEvent>(
            &mut contract_data.user_created_event,
            CreateUserEvent {
                email
            }
        );
    }

    public entry fun delete_user(user: &signer, email: String) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        smart_table::remove(&mut contract_data.users, email);

        emit_event<DeleteUserEvent>(
            &mut contract_data.user_deleted_event,
            DeleteUserEvent {
                email,
            }
        );
    }

    public entry fun update_user_score(
        user: &signer,
        email: String,
        avatar_name: String,
        new_score: u64
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        let (avatar_score, has_record, index) = has_record(&user_data.avatar_score, avatar_name, new_score);
        if (has_record) {
            let old_score = avatar_score.score;
            let updated_score = old_score + new_score;
            vector::remove(&mut user_data.avatar_score, index);
            vector::push_back(&mut user_data.avatar_score, AvatarScore {
                name: avatar_name,
                score: updated_score,
            });
        } else {
            vector::push_back(&mut user_data.avatar_score, AvatarScore {
                name: avatar_name,
                score: new_score,
            });
        };

        let user_score: u64 = 0;
        let index = 0;
        let len = vector::length(&user_data.avatar_score);
        while (index < len) {
            let avatar_score = *vector::borrow(&user_data.avatar_score, index);
            user_score = user_score + avatar_score.score;
            index = index + 1
        };
        user_data.score = user_score;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }


    public entry fun update_user_stake_tokens(user: &signer, email: String, stake_tokens: u64) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        user_data.stake_tokens = stake_tokens;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun add_user_stake_tokens(user: &signer, email: String, stake_tokens: u64) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        user_data.stake_tokens = user_data.stake_tokens + stake_tokens;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun add_user_inventory(user: &signer, email: String, inventory_item: String) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);

        //check if inventry exists
        let is_inventry_already_exists = vector::contains(&mut user_data.inventory, &inventory_item);
        assert!(!is_inventry_already_exists, ERROR_INVENTRY_EXISTS);

        vector::push_back(&mut user_data.inventory, inventory_item);

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun update_user_inventory(
        user: &signer,
        email: String,
        old_inventory_item: String,
        inventory_item: String
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);

        //check if inventory exists
        let is_inventory_exists = vector::contains(&mut user_data.inventory, &old_inventory_item);
        assert!(is_inventory_exists, ERROR_INVENTORY_NOT_EXISTS);

        vector::remove_value(&mut user_data.inventory, &old_inventory_item);
        vector::push_back(&mut user_data.inventory, inventory_item);

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun remove_user_inventory(user: &signer, email: String, inventory_item: String) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        vector::remove_value(&mut user_data.inventory, &inventory_item);

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun update_user(
        user: &signer,
        email: String,
        eth_wallet: address,
        aptos_wallet: address,
        aptos_custodial_wallet: address,
        username: String,
        stake_tokens: u64,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        user_data.eth_wallet = eth_wallet;
        user_data.aptos_wallet = aptos_wallet;
        user_data.aptos_custodial_wallet = aptos_custodial_wallet;
        user_data.username = username;
        user_data.stake_tokens = stake_tokens;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun update_user_basics(
        user: &signer,
        email: String,
        eth_wallet: address,
        aptos_wallet: address,
        aptos_custodial_wallet: address,
        username: String,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);


        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        user_data.eth_wallet = eth_wallet;
        user_data.aptos_wallet = aptos_wallet;
        user_data.aptos_custodial_wallet = aptos_custodial_wallet;
        user_data.username = username;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    // This method will update all user action and will be called periodically from backend
    public entry fun maintanence(
        user: &signer,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let now_sec = timestamp::now_seconds();

        for_each_mut(&mut contract_data.staked_v1_nfts, |staked_v1_nft| {
            if (now_sec - staked_v1_nft.staking_time >= POINT_EARNING_TIME) {
                staked_v1_nft.staking_time = now_sec;
                staked_v1_nft.points_earned = staked_v1_nft.points_earned + (staked_v1_nft.points_per_day * staked_v1_nft.amount);
            };
        });

        for_each_mut(&mut contract_data.staked_nfts, |staked_nft| {
            if (now_sec - staked_nft.staking_time >= POINT_EARNING_TIME) {
                staked_nft.staking_time = now_sec;
                staked_nft.points_earned = staked_nft.points_earned + staked_nft.points_per_day;
            };
        });

        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_keys = simple_map::keys(&mut users);

        vector::for_each(user_keys, |key| {
            let user_data = smart_table::borrow_mut(&mut contract_data.users, key);
            let (total_rewards, total_points, v2_points) = get_staker_reward(
                &contract_data.staked_nfts,
                user_data.aptos_wallet,
                user_data.aptos_custodial_wallet
            );
            let (total_rewards_v1, total_points_v1, v1_points) = get_staker_reward_v1(
                &contract_data.staked_v1_nfts,
                user_data.aptos_wallet,
                user_data.aptos_custodial_wallet
            );

            user_data.total_points_earned = total_points + total_points_v1;
            user_data.v1_points = v1_points;
            user_data.v2_points = v2_points;

            let user_reward_move = total_rewards + total_rewards_v1;
            if (user_data.last_cool_down_time != 0) {
                if (now_sec - user_data.last_cool_down_time > user_data.cool_down_timer / 2) {
                    user_data.remaining_actions = (user_data.max_actions + user_reward_move) / 2;
                };
                if (now_sec - user_data.last_cool_down_time > user_data.cool_down_timer) {
                    user_data.remaining_actions = (user_data.max_actions + user_reward_move);
                    user_data.last_cool_down_time = 0;
                };
            };
        });
    }

    public entry fun consume_user_action(
        user: &signer,
        email: String,
    ) acquires ContractData {
        let signer_address = signer::address_of(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_values = simple_map::values(&mut users);
        let email_address= string::utf8(b"");

        vector::for_each(user_values, |user| {
            if (signer_address == user.aptos_custodial_wallet || signer_address == user.aptos_wallet) {
                email_address = user.email;
            }
        });

        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email_address);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email_address);
        assert!(user_data.remaining_actions != 0, ERROR_ALL_ACTION_CONSUMED);

        user_data.remaining_actions = user_data.remaining_actions - 1;
        if (user_data.remaining_actions == 0) {
            user_data.last_cool_down_time = timestamp::now_seconds();
        };

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );
    }

    public entry fun update_user_action(
        user: &signer,
        email: String,
        actions_to_add: u64,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
        user_data.max_actions = user_data.max_actions + actions_to_add;
    }

    public entry fun add_action_pack(
        sender: &signer,
        action_type: String,
        action_name: String,
        action_price: u64,
        action_received: u64
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can assign new admin
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if avatar already exists
        assert!(!smart_table::contains(&contract_data.action_packs, action_type), ERROR_ACTION_PACK_ALREADY_EXISTS);

        let action_data = ActionData {
            name: action_name,
            price: action_price,
            action_received
        };

        smart_table::add(&mut contract_data.action_packs, action_type, action_data);

        emit_event<AddActionPackEvent>(
            &mut contract_data.add_action_pack_event,
            AddActionPackEvent {
                action_data,
                action_type,
            }
        );
    }

    public entry fun delete_action_pack(
        sender: &signer,
        action_type: String,
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can assign new admin
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if action pack not exists
        assert!(smart_table::contains(&contract_data.action_packs, action_type), ERROR_ACTION_PACK_NOT_EXISTS);

        smart_table::remove(&mut contract_data.action_packs, action_type);

        emit_event<DeleteActionPackEvent>(
            &mut contract_data.delete_action_pack_event,
            DeleteActionPackEvent {
                action_type,
            }
        );
    }

    public entry fun buy_action_pack(
        user: &signer,
        action_type: String,
        email: String,
    ) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        //check if action pack not exists
        assert!(smart_table::contains(&contract_data.action_packs, action_type), ERROR_ACTION_PACK_NOT_EXISTS);

        let action_data = *smart_table::borrow(&mut contract_data.action_packs, action_type);
        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);

        transfer_coins<AptosCoin>(user, contract_data.super_admin, action_data.price);
        user_data.max_actions = user_data.max_actions + action_data.action_received;

        emit_event<UpdateUserEvent>(
            &mut contract_data.user_updated_event,
            UpdateUserEvent {
                user_data: create(user_data)
            }
        );

        emit_event<BuyActionPackEvent>(
            &mut contract_data.buy_action_pack_event,
            BuyActionPackEvent {
                user_email: user_data.email,
                action_data
            }
        );
    }

    public entry fun stake_nft(staker: &signer, token_ids: vector<address>) acquires ContractData {
        let user_address = signer::address_of(staker);

        let all_valid = validate_nfts(token_ids);
        assert!(all_valid, ERROR_WRONG_COLLECTION);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let len = vector::length(&token_ids);
        let i = 0;
        while (i < len) {
            let token_id = *vector::borrow(&token_ids, i);
            let token = object::address_to_object<Tokenv2>(token_id);
            let collection = tokenv2::collection_object(token);
            let collection_address = object::object_address<Collection>(&collection);
            let whitelist_data = *smart_table::borrow(&mut contract_data.whitelist_data, collection_address);

            object::transfer(staker, token, RESOURCE_ACCOUNT);

            let stake_nft = StakedNFT {
                collection_address,
                token_id,
                staker: user_address,
                reward_moves: whitelist_data.extra_moves_on_staking,
                points_earned: 0,
                points_per_day: whitelist_data.points_per_day,
                staking_time: timestamp::now_seconds()
            };

            smart_vector::push_back(&mut contract_data.staked_nfts, stake_nft);

            emit_event<StakeNFTEvent>(
                &mut contract_data.stake_nft_event,
                StakeNFTEvent {
                    collection_address,
                    token_id,
                    staker: user_address,
                    reward_moves: whitelist_data.extra_moves_on_staking,
                    staking_time: timestamp::now_seconds(),
                    points_per_day: whitelist_data.points_per_day,
                }
            );

            i = i + 1;
        };
    }

    public entry fun unstake_nft(staker: &signer, token_ids: vector<address>) acquires ContractData {
        let user_address = signer::address_of(staker);

        let all_staked = validate_staked_nfts(user_address, token_ids);
        assert!(all_staked, ERROR_NFT_NOT_STAKED);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let resource_signer = &account::create_signer_with_capability(&contract_data.signer_cap);
        vector::for_each(token_ids, |token_id| {

            let token = object::address_to_object<Tokenv2>(token_id);
            object::transfer(resource_signer, token, user_address);

            // Find the index of the NFT to remove
            let maybe_index = find_staked_nft_index(&contract_data.staked_nfts, token_id);
            if (option::is_some(&maybe_index)) {
                let index = *option::borrow(&maybe_index);
                smart_vector::remove(&mut contract_data.staked_nfts, index);
            };

            emit_event<UnstakeNFTEvent>(
                &mut contract_data.unstake_nft_event,
                UnstakeNFTEvent {
                    token_id,
                    staker: user_address,
                }
            );
        });
    }


    public entry fun stake_nft_single(staker: &signer, token_id: address) acquires ContractData {
        let user_address = signer::address_of(staker);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let token = object::address_to_object<Tokenv2>(token_id);
        let collection = tokenv2::collection_object(token);
        let collection_address = object::object_address<Collection>(&collection);

        //check if token belongs to whitelist collection
        assert!(smart_table::contains(&contract_data.whitelist_data, collection_address), ERROR_WRONG_COLLECTION);

        let whitelist_data = *smart_table::borrow(&mut contract_data.whitelist_data, collection_address);

        object::transfer(staker, token, RESOURCE_ACCOUNT);

        let stake_nft = StakedNFT {
            collection_address,
            token_id,
            staker: user_address,
            reward_moves: whitelist_data.extra_moves_on_staking,
            points_earned: 0,
            points_per_day: whitelist_data.points_per_day,
            staking_time: timestamp::now_seconds()
        };

        smart_vector::push_back(&mut contract_data.staked_nfts, stake_nft);

        emit_event<StakeNFTEvent>(
            &mut contract_data.stake_nft_event,
            StakeNFTEvent {
                collection_address,
                token_id,
                staker: user_address,
                reward_moves: whitelist_data.extra_moves_on_staking,
                staking_time: timestamp::now_seconds(),
                points_per_day: whitelist_data.points_per_day,
            }
        );
    }

    public entry fun unstake_nft_single(staker: &signer, token_id: address) acquires ContractData {
        let user_address = signer::address_of(staker);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let index = option::none<u64>();

        let len = smart_vector::length(&contract_data.staked_nfts);
        let i = 0;
        while (i < len) {
            let staked_nft = smart_vector::borrow(&contract_data.staked_nfts, i);
            if (staked_nft.staker == user_address && staked_nft.token_id == token_id) {
                index = option::some(i);
                break
            };
            i = i + 1;
        };

        assert!(option::is_some(&index), ERROR_NFT_NOT_STAKED);
        let resource_signer = &account::create_signer_with_capability(&contract_data.signer_cap);
        let token = object::address_to_object<Tokenv2>(token_id);
        object::transfer(resource_signer, token, user_address);
        smart_vector::remove(&mut contract_data.staked_nfts, option::extract(&mut index));

        emit_event<UnstakeNFTEvent>(
            &mut contract_data.unstake_nft_event,
            UnstakeNFTEvent {
                token_id,
                staker: user_address,
            }
        );
    }

    public entry fun stake_v1_nft(
        staker: &signer,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        amount: u64
    ) acquires ContractData {
        let user_address = signer::address_of(staker);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if token belongs to whitelist creator
        assert!(smart_table::contains(&contract_data.whitelist_data, creator_address), ERROR_WRONG_COLLECTION);

        let resource_signer = &account::create_signer_with_capability(&contract_data.signer_cap);
        let token_id = tokenv1::create_token_id_raw(creator_address, collection_name, token_name, property_version);
        let token = tokenv1::withdraw_token(staker, token_id, amount);
        tokenv1::deposit_token(resource_signer, token);

        let whitelist_data = *smart_table::borrow(&mut contract_data.whitelist_data, creator_address) ;
        let reward_moves = whitelist_data.extra_moves_on_staking * amount;

        let index = get_staked_nft_data(
            &contract_data.staked_v1_nfts,
            user_address,
            creator_address,
            collection_name,
            token_name,
            property_version
        );
        if (option::is_some(&index)) {
            let staked_nft = smart_vector::borrow_mut(&mut contract_data.staked_v1_nfts, option::extract(&mut index));
            staked_nft.reward_moves = staked_nft.reward_moves + reward_moves;
            staked_nft.amount = staked_nft.amount + amount;
        } else {
            let stake_v1_nft = StakedV1NFT {
                staker: user_address,
                creator_address,
                collection_name,
                token_name,
                property_version,
                reward_moves,
                amount,
                points_earned: 0,
                staking_time: timestamp::now_seconds(),
                points_per_day: whitelist_data.points_per_day,
            };
            smart_vector::push_back(&mut contract_data.staked_v1_nfts, stake_v1_nft);
        };


        emit_event<StakeV1NFTEvent>(
            &mut contract_data.stake_v1_nft_event,
            StakeV1NFTEvent {
                staker: user_address,
                creator_address,
                collection_name,
                token_name,
                property_version,
                reward_moves,
                amount,
                staking_time: timestamp::now_seconds(),
                points_per_day: whitelist_data.points_per_day,
            }
        );
    }

    public entry fun unstake_nft_v1(
        staker: &signer,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        amount: u64
    ) acquires ContractData {
        let user_address = signer::address_of(staker);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let index = get_staked_nft_data(
            &contract_data.staked_v1_nfts,
            user_address,
            creator_address,
            collection_name,
            token_name,
            property_version
        );
        assert!(option::is_some(&index), ERROR_NFT_NOT_STAKED);
        let staked_nft_index = option::extract(&mut index);
        let staked_nft = smart_vector::borrow_mut(&mut contract_data.staked_v1_nfts, staked_nft_index);

        assert!(staked_nft.amount >= amount, ERROR_NFT_NOT_ENOUGH_AMOUNT);

        let whitelist_data = *smart_table::borrow(&mut contract_data.whitelist_data, creator_address);
        let reward_moves = whitelist_data.extra_moves_on_staking * amount;

        staked_nft.reward_moves = staked_nft.reward_moves - reward_moves;
        staked_nft.amount = staked_nft.amount - amount;

        let resource_signer = &account::create_signer_with_capability(&contract_data.signer_cap);
        let token_id = tokenv1::create_token_id_raw(creator_address, collection_name, token_name, property_version);
        let token = tokenv1::withdraw_token(resource_signer, token_id, amount);

        tokenv1::deposit_token(staker, token);

        if (staked_nft.amount == 0) {
            smart_vector::remove(&mut contract_data.staked_v1_nfts, staked_nft_index);
        };

        emit_event<UnstakeV1NFTEvent>(
            &mut contract_data.unstake_v1_nft_event,
            UnstakeV1NFTEvent {
                staker: user_address,
                creator_address,
                collection_name,
                token_name,
                property_version,
            }
        );
    }

    public entry fun create_pool<CoinType>(
        user: &signer,
        supply: u64,
        image_url: String,
        reward_amount: u64
    ) acquires ContractData {
        let user_address = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can create pool
        assert!(user_address == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if pool already exist with given coin
        assert!(!exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_EXIST);

        //check if given coin in initialized
        assert!(coin::is_coin_initialized<CoinType>(), ERROR_COIN_NOT_EXIST);

        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        let coin = coin::withdraw<CoinType>(user, supply);

        move_to(&resource_signer,
            PoolInfo<CoinType> {
                supply: coin,
                image_url,
                reward_amount,
            });

        let type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&type_info);

        emit_event<CreatePoolEvent>(
            &mut contract_data.create_pool_event,
            CreatePoolEvent {
                coin_address,
                supply,
                image_url,
                reward_amount,
            }
        );
    }


    public entry fun update_supply<CoinType>(
        user: &signer,
        supply_to_add: u64,
    ) acquires ContractData, PoolInfo {
        let user_address = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can add more supply
        assert!(user_address == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if pool exist with given coin
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT);

        transfer_in<CoinType>(&mut pool_info.supply, user, supply_to_add);

        let type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&type_info);

        emit_event<UpdateSupplyEvent>(
            &mut contract_data.update_supply_event,
            UpdateSupplyEvent {
                coin_address,
                supply: supply_to_add,
            }
        );
    }

    public entry fun update_reward<CoinType>(
        user: &signer,
        reward_amount: u64,
    ) acquires ContractData, PoolInfo {
        let user_address = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can update pool reward
        assert!(user_address == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if pool exist with given coin
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT);

        pool_info.reward_amount = reward_amount;

        let type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&type_info);

        emit_event<UpdateRewardEvent>(
            &mut contract_data.update_reward_event,
            UpdateRewardEvent {
                coin_address,
                reward_amount,
            }
        );
    }


    public entry fun send_reward<CoinType>(
        user: &signer,
        receiver_address: address,
    ) acquires ContractData, PoolInfo {
        //check only admin can call this method
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if pool exist with given coin
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT);

        transfer_out_account<CoinType>(&mut pool_info.supply, receiver_address, pool_info.reward_amount);

        let type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&type_info);

        emit_event<SendRewardEvent>(
            &mut contract_data.send_reward_event,
            SendRewardEvent {
                coin_address,
                receiver_address,
                reward_amount: pool_info.reward_amount
            }
        );
    }

    public entry fun withdraw_supply<CoinType>(
        user: &signer,
    ) acquires ContractData, PoolInfo {
        let user_address = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can withdraw supply
        assert!(user_address == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);

        //check if pool exist with given coin
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT);

        let amount = coin::value(&pool_info.supply);

        transfer_out<CoinType>(&mut pool_info.supply, user, amount);

        let type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&type_info);

        emit_event<WithdrawSupplyEvent>(
            &mut contract_data.withdraw_supply_event,
            WithdrawSupplyEvent {
                coin_address,
                receiver_address: user_address,
                withdraw_amount: amount,
            }
        );
    }

    #[view]
    public fun get_avatar(
        avatar_type: String
    ): (String, String, String, u64, String, vector<AvatarProperties>, address) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if avatar exists
        let is_already_exists = smart_table::contains(&contract_data.avatars, avatar_type);
        assert!(is_already_exists, ERROR_AVATAR_NOT_EXISTS);

        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, avatar_type);
        (
            avatar_data.name,
            avatar_data.description,
            avatar_data.type,
            avatar_data.price,
            avatar_data.token_uri,
            avatar_data.properties,
            avatar_data.royality_token_id
        )
    }

    #[view]
    public fun get_avatar_types(): ( vector<String>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let avatars = smart_table::to_simple_map(&mut contract_data.avatars);
        let avatar_keys = simple_map::keys(&mut avatars);

        (
            avatar_keys
        )
    }


    #[view]
    public fun get_user(
        email: String
    ): (address, address, address, String, u64, u64, u64, u64, u64, u64, u64, vector<String>, vector<AvatarScore>, vector<StakingReward>, vector<StakingReward>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if user exists
        let is_already_exists = smart_table::contains(&contract_data.users, email);
        assert!(is_already_exists, ERROR_USER_NOT_EXISTS);

        let user_data = smart_table::borrow(&contract_data.users, email);

        (
            user_data.eth_wallet,
            user_data.aptos_custodial_wallet,
            user_data.aptos_wallet,
            user_data.username,
            user_data.stake_tokens,
            user_data.score,
            user_data.remaining_actions,
            user_data.max_actions,
            user_data.last_cool_down_time,
            user_data.cool_down_timer,
            user_data.total_points_earned,
            user_data.inventory,
            user_data.avatar_score,
            user_data.v1_points,
            user_data.v2_points
        )
    }

    #[view]
    public fun get_users_in_range(
        start_index: u64, end_index: u64
    ): (vector<UserData>, u64) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_values = simple_map::values(&mut users);

        (
            vector::slice(&mut user_values, start_index, end_index),
            vector::length(&user_values)
        )
    }

    #[view]
    public fun get_royality(
        token_id: address,
    ): (u64) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let royality = if (smart_table::contains(&contract_data.royality_owners, token_id)) *smart_table::borrow(
            &contract_data.royality_owners,
            token_id
        ) else 0;

        (
            royality
        )
    }

    #[view]
    public fun get_staking_reward(
        user_adress: address,
    ): (u64, u64, vector<StakingReward>, vector<StakingReward>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let (total_rewards, total_points, v2_points) = get_staker_reward(
            &contract_data.staked_nfts,
            user_adress,
            user_adress
        );
        let (total_rewards_v1, total_points_v1, v1_points) = get_staker_reward_v1(
            &contract_data.staked_v1_nfts,
            user_adress,
            user_adress
        );
        (
            total_rewards + total_rewards_v1,
            total_points + total_points_v1,
            v1_points,
            v2_points
        )
    }

    #[view]
    public fun get_user_staked_nfts(
        user_adress: address,
    ): (vector<StakedNFT>, vector<StakedV1NFT>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let user_nfts = get_staked_nft(smart_vector::to_vector(&contract_data.staked_nfts), user_adress);
        let user_nfts_v1 = get_staked_nft_v1(smart_vector::to_vector(&contract_data.staked_v1_nfts), user_adress);

        (
            user_nfts, user_nfts_v1
        )
    }

    #[view]
    public fun get_whitelist_data(): (vector<WhitelistData>, vector<WhitelistData>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let collections = vector::empty<WhitelistData>();
        let creators = vector::empty<WhitelistData>();

        let whitelist_data = smart_table::to_simple_map(&mut contract_data.whitelist_data);
        let whitelist_addresses = simple_map::keys(&mut whitelist_data);

        vector::for_each(whitelist_addresses, |whitelist_address| {
            let data = *smart_table::borrow(&mut contract_data.whitelist_data, whitelist_address);
            if (object::object_exists<Collection>(whitelist_address)) {
                vector::push_back(&mut collections, data);
            }else {
                vector::push_back(&mut creators, data);
            }
        });

        (
            collections, creators
        )
    }

    #[view]
    public fun get_pool_info<CoinType>(): (u64, u64, String) acquires PoolInfo {
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT), ERROR_POOL_NOT_EXIST);
        let pool_info = borrow_global<PoolInfo<CoinType>>(RESOURCE_ACCOUNT);
        (
            coin::value(&pool_info.supply),
            pool_info.reward_amount,
            pool_info.image_url,
        )
    }

    #[view]
    public fun get_leaderboard(start_index: u64, end_index: u64): (vector<UserData>, u64) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_values = simple_map::values(&mut users);


        let sorted_leader_board = *sort_vector(&mut user_values);
        (
            vector::slice(&sorted_leader_board, start_index, end_index),
            vector::length(&sorted_leader_board)
        )
    }

    #[view]
    public fun get_leaderboard_length(): ( u64) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_values = simple_map::values(&mut users);

        (
            vector::length(&user_values)
        )
    }

    fun create(
        user_data: &mut UserData
    ): UserData {
        UserData {
            email: user_data.email,
            eth_wallet: user_data.eth_wallet,
            aptos_wallet: user_data.aptos_wallet,
            aptos_custodial_wallet: user_data.aptos_custodial_wallet,
            username: user_data.username,
            stake_tokens: user_data.stake_tokens,
            score: user_data.score,
            remaining_actions: user_data.remaining_actions,
            max_actions: user_data.max_actions,
            cool_down_timer: user_data.cool_down_timer,
            last_cool_down_time: user_data.last_cool_down_time,
            avatar_score: user_data.avatar_score,
            inventory: user_data.inventory,
            total_points_earned: user_data.total_points_earned,
            v1_points: user_data.v1_points,
            v2_points: user_data.v2_points,
        }
    }

    fun mint_token(
        contract_data: &mut ContractData,
        avatar_type: String,
        receiver_address: address,
        is_soul_bound: bool
    ) {
        let avatar_data = smart_table::borrow_mut(&mut contract_data.avatars, avatar_type);

        // Getting all contract related data that will be used to mint token
        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        // The collection name is used to locate the collection object and to create a new token object.
        let collection = string::utf8(COLLECTION_NAME);

        // Creates the avatar token, and get the constructor ref of the token. The constructor ref
        // is used to generate the refs of the token.
        let name_str = avatar_data.name;
        string::append(&mut name_str, string::utf8(b" #"));
        string::append(&mut name_str, to_string<u64>(&avatar_data.position));
        let constructor_ref = tokenv2::create_named_token(
            &resource_signer,
            collection,
            avatar_data.description,
            name_str,
            option::none(),
            avatar_data.token_uri,
        );
        avatar_data.position = avatar_data.position + 1;

        // Generates the object signer and the refs.  The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let mutator_ref = tokenv2::generate_mutator_ref(&constructor_ref);
        let burn_ref = tokenv2::generate_burn_ref(&constructor_ref);
        let property_mutator_ref = property_map::generate_mutator_ref(&constructor_ref);

        // Transfers the token to the `soul_bound_to` address
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver_address);

        // Disables ungated transfer, thus making the token soulbound and non-transferable
        if (is_soul_bound) {
            object::disable_ungated_transfer(&transfer_ref);
        };

        // Initialize the property map and the avatar rank as Bronze
        let properties = property_map::prepare_input(vector[], vector[], vector[]);
        property_map::init(&constructor_ref, properties);
        let i = 0;

        while (i < vector::length(&avatar_data.properties)) {
            let property = *vector::borrow(&avatar_data.properties, i);
            property_map::add_typed(
                &property_mutator_ref,
                property.key,
                property.value
            );
            i = i + 1
        };

        // Publishes the AvatarToken resource with the refs.
        let avatar_token = AvatarToken {
            head_gear: option::none(),
            weapon_equipped: option::none(),
            inventory: option::none(),
            armor: option::none(),
            shoes: option::none(),
            transfer_ref: option::some(transfer_ref),
            mutator_ref,
            burn_ref,
            property_mutator_ref,
        };

        move_to(&object_signer, avatar_token);
    }


    fun create_avatar_collection(creator: &signer) {
        // Constructs the strings from the bytes.
        let description = string::utf8(COLLECTION_DESCRIPTION);
        let name = string::utf8(COLLECTION_NAME);
        let uri = string::utf8(COLLECTION_URI);

        // Creates the collection with unlimited supply and without establishing any royalty configuration.
        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }


    fun authorize_only_admin(user: &signer) acquires ContractData {
        let sender_addres = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        //only admin can perform this operation
        assert!(vector::contains(&mut contract_data.admin, &sender_addres), ERROR_ONLY_ADMIN);
    }

    /// Implements: `x` * `y` / `z`.
    public fun mul_div(x: u64, y: u64, z: u64): u64 {
        assert!(z != 0, ERROR_DIVIDE_BY_ZERO);
        let r = (x as u128) * (y as u128) / (z as u128);
        (r as u64)
    }

    fun transfer_out_account<CoinType>(own_coin: &mut coin::Coin<CoinType>, receiver: address, amount: u64) {
        let extract_coin = coin::extract<CoinType>(own_coin, amount);
        aptos_account::deposit_coins(receiver, extract_coin);
    }

    fun transfer_in<CoinType>(own_coin: &mut coin::Coin<CoinType>, account: &signer, amount: u64) {
        let coin = coin::withdraw<CoinType>(account, amount);
        coin::merge(own_coin, coin);
    }

    fun transfer_out<CoinType>(own_coin: &mut coin::Coin<CoinType>, receiver: &signer, amount: u64) {
        check_or_register_coin_store<CoinType>(receiver);
        let extract_coin = coin::extract<CoinType>(own_coin, amount);
        coin::deposit<CoinType>(signer::address_of(receiver), extract_coin);
    }

    fun check_or_register_coin_store<CoinType>(sender: &signer) {
        if (!coin::is_account_registered<CoinType>(signer::address_of(sender))) {
            coin::register<CoinType>(sender);
        };
    }

    fun calculate_royality(user: &signer, contract_data: &mut ContractData, avatar_data: AvatarData) {
        if (avatar_data.royality_token_id == NULL_ADDRESS) {
            transfer_coins<AptosCoin>(user, contract_data.super_admin, avatar_data.price);
        } else {
            let royality = mul_div(avatar_data.price, ROYALITY_NUMERATOR, ROYALITY_DENOMINATOR);
            let price_after_royality = avatar_data.price - royality;

            transfer_in<AptosCoin>(&mut contract_data.royality, user, royality);

            transfer_coins<AptosCoin>(user, contract_data.super_admin, price_after_royality);

            if (smart_table::contains(&contract_data.royality_owners, avatar_data.royality_token_id)) {
                let old_royality = *smart_table::borrow(
                    &mut contract_data.royality_owners,
                    avatar_data.royality_token_id
                );
                let new_royality = old_royality + royality;
                smart_table::upsert(&mut contract_data.royality_owners, avatar_data.royality_token_id, new_royality);
            } else {
                smart_table::add(&mut contract_data.royality_owners, avatar_data.royality_token_id, royality);
            };
        };
    }


    inline fun has_record(
        avatar_scores: &vector<AvatarScore>,
        avatar_name: String,
        avatar_score: u64
    ): (&AvatarScore, bool, u64) {
        let avatar_score: &AvatarScore = &AvatarScore {
            name: avatar_name,
            score: avatar_score,
        };
        let has_record: bool = false;
        let index_of_record: u64 = 0;
        let len = vector::length(avatar_scores);
        while (index_of_record < len) {
            let record = vector::borrow(avatar_scores, index_of_record);
            if (record.name == avatar_name) {
                avatar_score = record;
                has_record = true;
                break
            };
            index_of_record = index_of_record + 1
        };
        (avatar_score, has_record, index_of_record)
    }

    fun get_staked_nft(
        staked_nfts: vector<StakedNFT>,
        staker_address: address
    ): vector<StakedNFT> {
        let user_nfts = vector::empty<StakedNFT>();

        vector::for_each(staked_nfts, |staked_nft| {
            if (staked_nft.staker == staker_address) {
                vector::push_back(&mut user_nfts, staked_nft);
            }
        });

        user_nfts
    }

    fun get_staked_nft_v1(
        staked_v1_nfts: vector<StakedV1NFT>,
        staker_address: address
    ): vector<StakedV1NFT> {
        let user_nfts = vector::empty<StakedV1NFT>();

        vector::for_each(staked_v1_nfts, |staked_nft| {
            if (staked_nft.staker == staker_address) {
                vector::push_back(&mut user_nfts, staked_nft);
            }
        });

        user_nfts
    }

    fun get_staker_reward(
        staked_nfts: &SmartVector<StakedNFT>,
        staker_address: address,
        staker_custodian_address: address
    ): (u64, u64, vector<StakingReward>) {
        let total_rewards: u64 = 0;
        let total_points: u64 = 0;
        let v2_points = vector::empty<StakingReward>();

        smart_vector::for_each_ref(staked_nfts, |staked_nft| {
            if (staked_nft.staker == staker_address || staked_nft.staker == staker_custodian_address) {
                total_rewards = total_rewards + staked_nft.reward_moves;
                total_points = total_points + staked_nft.points_earned;
                let has_reward = has_reward(staked_nft.collection_address, v2_points);
                if (option::is_some(&has_reward)) {
                    let index = option::extract(&mut has_reward);
                    let reward = vector::borrow_mut(&mut v2_points, index);
                    reward.extra_moves_on_staking = reward.extra_moves_on_staking + staked_nft.reward_moves;
                    reward.points_per_day = reward.points_per_day + staked_nft.points_per_day;
                    reward.points_earned = reward.points_earned + staked_nft.points_earned;
                } else {
                    vector::push_back(&mut v2_points, StakingReward {
                        address: staked_nft.collection_address,
                        extra_moves_on_staking: staked_nft.reward_moves,
                        points_per_day: staked_nft.points_per_day,
                        points_earned: staked_nft.points_earned
                    });
                }
            }
        });

        (total_rewards, total_points, v2_points)
    }

    fun get_staker_reward_v1(
        staked_v1_nfts: &SmartVector<StakedV1NFT>,
        staker_address: address,
        staker_custodian_address: address
    ): (u64, u64, vector<StakingReward>) {
        let total_rewards: u64 = 0;
        let total_points: u64 = 0;
        let v1_points = vector::empty<StakingReward>();
        smart_vector::for_each_ref(staked_v1_nfts, |staked_nft| {
            if (staked_nft.staker == staker_address || staked_nft.staker == staker_custodian_address) {
                total_rewards = total_rewards + staked_nft.reward_moves;
                total_points = total_points + staked_nft.points_earned;
                let has_reward = has_reward(staked_nft.creator_address, v1_points);
                if (option::is_some(&has_reward)) {
                    let index = option::extract(&mut has_reward);
                    let reward = vector::borrow_mut(&mut v1_points, index);
                    reward.extra_moves_on_staking = reward.extra_moves_on_staking + staked_nft.reward_moves;
                    reward.points_per_day = reward.points_per_day + (staked_nft.points_per_day * staked_nft.amount);
                    reward.points_earned = reward.points_earned + staked_nft.points_earned;
                } else {
                    vector::push_back(&mut v1_points, StakingReward {
                        address: staked_nft.creator_address,
                        extra_moves_on_staking: staked_nft.reward_moves,
                        points_per_day: staked_nft.points_per_day * staked_nft.amount,
                        points_earned: staked_nft.points_earned,
                    });
                }
            }
        });
        (total_rewards, total_points, v1_points)
    }

    fun has_reward(
        address: address,
        rewards: vector<StakingReward>,
    ): (Option<u64>) {
        let index = option::none<u64>();
        let i = 0;
        vector::for_each(rewards, |reward| {
            if (reward.address == address) {
                index = option::some(i);
            };
            i = i + 1;
        });
        (index)
    }

    fun get_staked_nft_data(
        staked_v1_nfts: &SmartVector<StakedV1NFT>,
        user_address: address,
        creator_address: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ): ( Option<u64>) {
        let index = option::none<u64>();
        let len = smart_vector::length(staked_v1_nfts);
        let i = 0;
        while (i < len) {
            let staked_nft = smart_vector::borrow(staked_v1_nfts, i);
            if (staked_nft.staker == user_address
                && staked_nft.creator_address == creator_address
                && staked_nft.collection_name == collection_name
                && staked_nft.token_name == token_name
                && staked_nft.property_version == property_version) {
                index = option::some(i);
                break
            };
            i = i + 1;
        };

        index
    }

    fun validate_nfts(token_ids: vector<address>): (bool) acquires ContractData {
        let contract_data = borrow_global<ContractData>(RESOURCE_ACCOUNT);

        let all_valid = true;

        vector::for_each(token_ids, |token_id| {
            let token = object::address_to_object<Tokenv2>(token_id);
            let collection = tokenv2::collection_object(token);
            let collection_address = object::object_address<Collection>(&collection);

            //check if all tokens belongs to whitelist collections
            if (!smart_table::contains(&contract_data.whitelist_data, collection_address)) {
                all_valid = false;
            }
        });

        all_valid
    }

    fun validate_staked_nfts(
        staker_address: address,
        token_ids: vector<address>
    ): (bool) acquires ContractData {
        let contract_data = borrow_global<ContractData>(RESOURCE_ACCOUNT);

        let staked_data = vector::empty<address>();

        vector::for_each(token_ids, |token_id| {
            smart_vector::for_each_ref(&contract_data.staked_nfts, |staked_nft| {
                if (staked_nft.token_id == token_id && staked_nft.staker == staker_address) {
                    vector::push_back(&mut staked_data, token_id);
                };
            });
        });

        (vector::length(&token_ids) == vector::length(&staked_data))
    }

    fun get_leaderboard_data(
        leaderboard_data: &vector<LeaderBoardData>,
        staker: address,
    ): ( Option<u64>) {
        let index = option::none<u64>();
        let len = vector::length(leaderboard_data);
        let i = 0;
        while (i < len) {
            let data = vector::borrow(leaderboard_data, i);
            if (data.staker == staker) {
                index = option::some(i);
                break
            };
            i = i + 1;
        };

        index
    }

    public fun sort_vector(v: &mut vector<UserData>): &mut vector<UserData> {
        let len = vector::length(v);
        let i = 0;

        // Outer loop
        while (i < len) {
            let j = 0;

            // Inner loop
            while (j < len - i - 1) {
                let a = *vector::borrow(v, j);
                let b = *vector::borrow(v, j + 1);
                if (a.total_points_earned < b.total_points_earned) {
                    // Swap the elements
                    vector::swap(v, j, j + 1);
                };
                j = j + 1;
            };

            i = i + 1;
        };

        v
    }

    fun find_staked_nft_index(
        staked_nfts: &smart_vector::SmartVector<StakedNFT>,
        token_id: address
    ): Option<u64> {
        let len = smart_vector::length(staked_nfts);
        let i = 0;
        while (i < len) {
            let nft = smart_vector::borrow(staked_nfts, i);
            if (nft.token_id == token_id) {
                return option::some(i);
            };
            i = i + 1;
        };
        option::none()
    }

}
