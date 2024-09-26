module jungle_run::jungle_run {
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::smart_table;
    use aptos_std::smart_table::{SmartTable};
    use aptos_framework::account;
    use aptos_framework::aptos_account::transfer_coins;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::code;
    use aptos_framework::coin;
    use aptos_framework::event::{emit_event, EventHandle};
    use aptos_framework::object;
    use aptos_framework::object::{Object, TransferRef};
    use aptos_framework::resource_account;
    use aptos_std::string_utils::{to_string};
    use aptos_framework::timestamp;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

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

        // Store address of whitelist collection
        whitelist_collection: vector<address>,

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
        inventory: vector<String>
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
        is_soul_bound: bool
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

    // NFT related structures
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AvatarToken has key {
        head_gear: Option<Object<HeadGear>>,
        weapon_equipped: Option<Object<Weapon>>,
        inventory: Option<Object<Inventry>>,
        armor: Option<Object<Armor>>,
        shoes: Option<Object<Shoes>>,

        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct HeadGear has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Weapon has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }


    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Inventry has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Armor has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Shoes has key {
        transfer_ref: Option<TransferRef>,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
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
            whitelist_collection: vector::empty<address>(),
            avatars: smart_table::new<String, AvatarData>(),
            users: smart_table::new<String, UserData>(),
            action_packs: smart_table::new<String, ActionData>(),
            royality: coin::zero<AptosCoin>(),
            royality_owners: smart_table::new<address, u64>(),
            user_created_event: account::new_event_handle<CreateUserEvent>(sender),
            user_updated_event: account::new_event_handle<UpdateUserEvent>(sender),
            user_deleted_event: account::new_event_handle<DeleteUserEvent>(sender),
            token_property_event: account::new_event_handle<TokenPropertyEvent>(sender),
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

    public entry fun add_whitelist_collection(sender: &signer, collection_address: address) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //Only super admin can white list collection
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);
        vector::push_back(&mut contract_data.whitelist_collection, collection_address);
    }

    public entry fun remove_whitelist_collection(sender: &signer, collection_address: address) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //Only super admin can white list collection
        assert!(sender_addr == contract_data.super_admin, ERROR_ONLY_SUPER_ADMIN);
        vector::remove_value(&mut contract_data.whitelist_collection, &collection_address);
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
        royality_token_id: address,
        is_soul_bound: bool
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can assign new admin
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
            is_soul_bound
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

        //only super admin can assign new admin
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

        //only super admin can assign new admin
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

        //only super admin can assign new admin
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

        //only super admin can assign new admin
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

    // Mints free token. This function mints a new soul bound token to user address.
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

    // Mints token. This function mints a new token to receiver address.
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

    // Mints token. This function mints a new token to user address who own nft from proud lions.
    public entry fun mint_free_avatar(
        user: &signer,
        avatar_type: String,
        token_id: address,
    ) acquires ContractData {
        let sender_addres = signer::address_of(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let token = object::address_to_object<Token>(token_id);
        let collection = token::collection_object(token);
        let collection_address = object::object_address<Collection>(&collection);

        //check if avatar type not exists
        assert!(smart_table::contains(&contract_data.avatars, avatar_type), ERROR_AVATAR_NOT_EXISTS);

        //check if token belongs to whitelist collection
        assert!(vector::contains(&contract_data.whitelist_collection, &collection_address), ERROR_WRONG_COLLECTION);

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
        let token = object::address_to_object<Token>(token_id);
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

        token::set_uri(&avatar_token.mutator_ref, new_token_uri);
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

        token::set_name(&avatar_token.mutator_ref, new_name);
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

        token::set_description(&avatar_token.mutator_ref, new_decs);
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
    public entry fun update_user_actions(
        user: &signer,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let users = smart_table::to_simple_map(&mut contract_data.users);
        let user_values = simple_map::values(&mut users);
        let length = vector::length(&user_values);
        let i = 0;

        while (i < length) {
            let user = *vector::borrow(&user_values, i);

            let user_data = smart_table::borrow_mut(&mut contract_data.users, user.email);
            if (user_data.last_cool_down_time == 0) {
                continue
            } else {
                let now_sec = timestamp::now_seconds();
                if (now_sec - user_data.last_cool_down_time > user_data.cool_down_timer / 2) {
                    user_data.remaining_actions = user_data.max_actions / 2;
                };
                if (now_sec - user_data.last_cool_down_time > user_data.cool_down_timer) {
                    user_data.remaining_actions = user_data.max_actions;
                    user_data.last_cool_down_time = 0;
                };
            };

            i = i + 1;
        };
    }

    public entry fun consume_user_action(
        user: &signer,
        email: String,
    ) acquires ContractData {
        //check authentication of admin
        authorize_only_admin(user);

        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let user_data = smart_table::borrow_mut(&mut contract_data.users, email);
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

        let data = ActionData {
            name: action_name,
            price: action_price,
            action_received
        };

        smart_table::add(&mut contract_data.action_packs, action_type, data);
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
        assert!(smart_table::contains(&contract_data.action_packs, action_type), ERROR_ACTION_PACK_ALREADY_EXISTS);

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
    ): (address, address, address, String, u64, u64, u64, u64, u64, u64, vector<String>, vector<AvatarScore>) acquires ContractData {
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
            user_data.inventory,
            user_data.avatar_score
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
        let constructor_ref = token::create_named_token(
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
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
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
}
