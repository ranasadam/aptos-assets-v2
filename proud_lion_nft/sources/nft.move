module proud_lion::nft {
    use std::bcs;
    use std::error;
    use std::option;
    use std::signer;
    use std::string;
    use aptos_std::string_utils::to_string;
    use std::string::{String};
    use aptos_std::simple_map;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::code;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_framework::resource_account;
    use aptos_token::token as tokenv1;

    use aptos_token_objects::collection;
    use aptos_token_objects::token as tokenv2;

    const NULL_ADDRESS: address = @null_address;
    const RESOURCE_ACCOUNT: address = @proud_lion;
    const DEFAULT_ADMIN: address = @proud_lion_default_admin;
    const DEV: address = @proud_lion_dev;

    // Errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_LION_NOT_EXISTS: u64 = 1;
    const ERROR_TOKEN_DOES_NOT_EXIST: u64 = 2;
    const ERROR_NOT_OWNER: u64 = 3;

    const BURNABLE_BY_OWNER: vector<u8> = b"TOKEN_BURNABLE_BY_OWNER";
    const BURNABLE_BY_CREATOR: vector<u8> = b"TOKEN_BURNABLE_BY_CREATOR";

    // The lion token collection name
    const COLLECTION_NAME: vector<u8> = b"Proud Lion";
    // The lion token collection description
    const COLLECTION_DESCRIPTION: vector<u8> = b"This collection proud lion collection";
    // The lion token collection URI
    const COLLECTION_URI: vector<u8> = b"Proud Lion Collection URI";

    struct ContractData has key {
        signer_cap: account::SignerCapability,
        admin: address,

        // Smart table to store lion of different type
        lions: SmartTable<String, LionData>,
        // Index of v1 token that will append with name to make it unique
        v1_index: u64
    }


    struct LionData has copy, store, drop {
        name: String,
        description: String,
        token_uri: String,
    }

    // NFT related structures
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct LionToken has key {
        mutator_ref: tokenv2::MutatorRef,
        burn_ref: tokenv2::BurnRef,
    }

    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);

        let collection_name = string::utf8(COLLECTION_NAME);
        let description = string::utf8(COLLECTION_DESCRIPTION);
        let collection_uri = string::utf8(COLLECTION_URI);

        // This means that the supply of the token will not be tracked.
        let maximum_supply = 0;
        // This variable sets if we want to allow mutation for collection description, uri, and maximum.
        // Here, we are setting all of them to false, which means that we don't allow mutations to any CollectionData fields.
        let mutate_setting = vector<bool>[ false, false, false ];

        // Create the nft v1 collection.
        tokenv1::create_collection(
            &resource_signer,
            collection_name,
            description,
            collection_uri,
            maximum_supply,
            mutate_setting
        );

        move_to(&resource_signer, ContractData {
            admin: DEFAULT_ADMIN,
            signer_cap,
            lions: getLionsData(),
            v1_index: 1,
        });
        create_proud_lion_collection(&resource_signer);
    }

    public entry fun set_admin(sender: &signer, new_admin: address) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let metadata = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //Only super admin can assign new super admin
        assert!(sender_addr == metadata.admin, ERROR_ONLY_ADMIN);
        metadata.admin = new_admin;
    }


    public entry fun upgrade_contract(
        sender: &signer,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>
    ) acquires ContractData {
        let sender_addr = signer::address_of(sender);
        let metadata = borrow_global<ContractData>(RESOURCE_ACCOUNT);

        //only super admin can upgrade this contract
        assert!(sender_addr == metadata.admin, ERROR_ONLY_ADMIN);
        let resource_signer = account::create_signer_with_capability(&metadata.signer_cap);
        code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    public entry fun mint_lion(
        user: &signer,
        lion_type: String,
    ) acquires ContractData {
        let sender_address = signer::address_of(user);
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if lion type not exists
        assert!(smart_table::contains(&contract_data.lions, lion_type), ERROR_LION_NOT_EXISTS);

        let lion_data = smart_table::borrow(&contract_data.lions, lion_type);
        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        // The collection name is used to locate the collection object and to create a new token object.
        let collection = string::utf8(COLLECTION_NAME);

        let name_str = lion_data.name;
        string::append(&mut name_str, string::utf8(b" #"));
        let constructor_ref = tokenv2::create_numbered_token(
            &resource_signer,
            collection,
            lion_data.description,
            name_str,
            string::utf8(b""),
            option::none(),
            lion_data.token_uri,
        );

        // Generates the object signer and the refs.  The refs are used to manage the token.
        let object_signer = object::generate_signer(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let mutator_ref = tokenv2::generate_mutator_ref(&constructor_ref);
        let burn_ref = tokenv2::generate_burn_ref(&constructor_ref);

        // Transfers the token to the address
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, sender_address);

        // Publishes the Lion resource with the refs.
        let lion_token = LionToken {
            mutator_ref,
            burn_ref,
        };

        move_to(&object_signer, lion_token);
    }

    public entry fun burn_lion(user: &signer, token: Object<LionToken>) acquires LionToken {
        assert!(
            object::is_owner(token, signer::address_of(user)),
            error::not_found(ERROR_NOT_OWNER),
        );
        let lion_token = move_from<LionToken>(object::object_address(&token));
        let LionToken {
            mutator_ref: _,
            burn_ref,
        } = lion_token;

        tokenv2::burn(burn_ref);
    }

    public entry fun mint_lion_v1(
        receiver: &signer,
        lion_type: String,
        amount: u64
    ) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);

        //check if lion type not exists
        assert!(smart_table::contains(&contract_data.lions, lion_type), ERROR_LION_NOT_EXISTS);

        let lion_data = smart_table::borrow(&contract_data.lions, lion_type);

        let token_name: string::String = lion_data.name ;
        string::append_utf8(&mut token_name, b" ");
        string::append(&mut token_name, to_string<u64>(&contract_data.v1_index));

        let token_data_id = tokenv1::create_tokendata(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            token_name,
            lion_data.description,
            0,
            lion_data.token_uri,
            DEFAULT_ADMIN,
            1,
            0,
            tokenv1::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ),
            vector<String>[string::utf8(BURNABLE_BY_CREATOR), string::utf8(BURNABLE_BY_OWNER)],
            vector<vector<u8>>[ bcs::to_bytes<bool>(&true), bcs::to_bytes<bool>(&true)],
            vector<String>[ string::utf8(b"bool"), string::utf8(b"bool") ],
        );

        let resource_signer = account::create_signer_with_capability(&contract_data.signer_cap);
        let token_id = tokenv1::mint_token(&resource_signer, token_data_id, amount);
        tokenv1::direct_transfer(&resource_signer, receiver, token_id, amount);

        contract_data.v1_index = contract_data.v1_index + 1;
    }

    public entry fun burn_lion_v1(
        user: &signer,
        token_name: String,
        property_version: u64,
        amount: u64
    ) {
        tokenv1::burn(user, RESOURCE_ACCOUNT, string::utf8(COLLECTION_NAME), token_name, property_version, amount);
    }

    #[view]
    public fun get_Lion(
        lion_type: String
    ): (String, String, String) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        //check if lion exists
        let is_already_exists = smart_table::contains(&contract_data.lions, lion_type);
        assert!(is_already_exists, ERROR_LION_NOT_EXISTS);

        let lion_data = smart_table::borrow_mut(&mut contract_data.lions, lion_type);
        (
            lion_data.name,
            lion_data.description,
            lion_data.token_uri,
        )
    }

    #[view]
    public fun get_lion_types(): ( vector<String>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(RESOURCE_ACCOUNT);

        let lions = smart_table::to_simple_map(&mut contract_data.lions);
        let lion_keys = simple_map::keys(&mut lions);

        (
            lion_keys
        )
    }

    fun create_proud_lion_collection(creator: &signer) {
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

    fun getLionsData(): SmartTable<String, LionData> {
        let lions = smart_table::new<String, LionData>();
        smart_table::add(&mut lions, string::utf8(b"ALPHA"), LionData {
            name: string::utf8(b"Aplha Lion"),
            description: string::utf8(b"This lion can only be acquired from the Lioness Ritual"),
            token_uri: string::utf8(b"https://api.proudlionsclub.com/tokenids/587.json"),
        });
        smart_table::add(&mut lions, string::utf8(b"BETA"), LionData {
            name: string::utf8(b"Beta Lion"),
            description: string::utf8(b"This lion get royality when character mints"),
            token_uri: string::utf8(b"https://api.proudlionsclub.com/tokenids/5000.json"),
        });
        lions
    }
}
