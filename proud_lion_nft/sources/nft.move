module proud_lion::nft {
    use std::error;
    use std::option;
    use std::signer;
    use std::string;
    use std::string::String;
    use aptos_std::simple_map;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::code;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_framework::resource_account;

    use aptos_token_objects::collection;
    use aptos_token_objects::token;

    const NULL_ADDRESS: address = @null_address;
    const RESOURCE_ACCOUNT: address = @proud_lion;
    const DEFAULT_ADMIN: address = @proud_lion_default_admin;
    const DEV: address = @proud_lion_dev;

    // Errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_LION_NOT_EXISTS: u64 = 1;
    const ERROR_TOKEN_DOES_NOT_EXIST: u64 = 2;
    const ERROR_NOT_OWNER: u64 = 3;


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
    }


    struct LionData has copy, store, drop {
        name: String,
        description: String,
        token_uri: String,
    }

    // NFT related structures
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct LionToken has key {
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
    }

    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);


        move_to(&resource_signer, ContractData {
            admin: DEFAULT_ADMIN,
            signer_cap,
            lions: getLionsData(),
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
        let constructor_ref = token::create_numbered_token(
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
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);

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

        token::burn(burn_ref);
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
