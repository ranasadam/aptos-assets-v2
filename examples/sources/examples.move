module jungle_run::examples {
    use std::string;
    use std::string::String;
    use aptos_framework::account;
    use aptos_framework::event::{emit_event, EventHandle};
    use aptos_framework::object;
    use aptos_framework::object::{Object, object_address};
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

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

    public entry fun burn_nft(owner: &signer, token: Object<Token>) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(DEFAULT_ADMIN);

        let chest_type = property_map::read_string(&token, &string::utf8(CHEST_TYPE_KEY));
        object::burn(owner, token);

        emit_event<TokenPropertyEvent>(
            &mut contract_data.token_property_event,
            TokenPropertyEvent {
                token_address: object_address(&token),
                chest_type,
            }
        );
    }

    #[lint::allow_unsafe_randomness]
    #[randomness]
    entry fun check_randomness(
        start_range: u64, end_range: u64
    ) acquires ContractData {
        let contract_data = borrow_global_mut<ContractData>(DEFAULT_ADMIN);

        let random = aptos_framework::randomness::u64_range(start_range, end_range);
        emit_event<RandomEvent>(
            &mut contract_data.random_event,
            RandomEvent {
                random,
            }
        );
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
