module jungle_run::examples {
    use std::string::String;
    use aptos_framework::account;
    use aptos_framework::event::EventHandle;
    use aptos_framework::object;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;
    use aptos_token_objects::collection::Collection;

    const DEFAULT_ADMIN: address = @jungle_run;

    // The chest token on chain property type
    const CHEST_TYPE_KEY: vector<u8> = b"ChestType";

    struct TokenPropertyEvent has drop, store {
        token_address: address,
        chest_type: String,
    }

    struct RandomEvent has drop, store {
        random: u64,
    }

    struct ContractData has key {
        admin: address,
        token_property_event: EventHandle<TokenPropertyEvent>,
        random_event: EventHandle<RandomEvent>,
    }

    fun init_module(sender: &signer) {
        move_to(sender, ContractData {
            admin: DEFAULT_ADMIN,
            token_property_event: account::new_event_handle<TokenPropertyEvent>(sender),
            random_event: account::new_event_handle<RandomEvent>(sender),
        });
    }


    #[view]
    public fun check_owner(
        token_id: address, owner: address
    ): (bool) {
        let token = object::address_to_object<Token>(token_id);
        (
            object::is_owner(token, owner)
        )
    }


    #[view]
    public fun check_collection(
        token_id: address
    ): (address) {
        let token = object::address_to_object<Token>(token_id);
        let collection = token::collection_object(token);
        let collection_address = object::object_address<Collection>(&collection);

        (
            collection_address
        )
    }
}
