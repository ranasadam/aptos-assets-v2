module jungle_run::examples {
    use aptos_framework::object;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    const DEFAULT_ADMIN: address = @jungle_run;

    struct ContractData has key {
        admin: address,
    }

    fun init_module(sender: &signer) {
        move_to(sender, ContractData {
            admin: DEFAULT_ADMIN,
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
