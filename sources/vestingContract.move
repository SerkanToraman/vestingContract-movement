module vestingContract::VestingContract {
    use aptos_std::table::{Self, Table};
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::debug;
    use std::timestamp;
    use std::string;   


    /// Errors
    const E_NOT_OWNER: u64 = 0; 
    const E_USER_ALREADY_EXISTS: u64 = 1; 
    const E_NO_VESTED_AMOUNT: u64 = 2; 
    const E_INVALID_TOTAL_AMOUNT: u64 = 3;
    const E_INVALID_CLAIM_AMOUNT: u64 = 4;
    const E_CLAIM_AMOUNT_EXCEEDS_CLAIMABLE: u64 = 5;


    /// Storage for vesting streams managed by the owner
    struct VestingStreams has key {
        streams: Table<address, VestingStream>,
    }

    /// Structure representing a vesting stream
    struct VestingStream has key, store, drop {
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64,
        claimed_amount: u64,
    }

    /// Asserts that the provided address is the owner.
    /// This is used to enforce owner-only actions.
    public fun assert_is_owner(addr: address) {
        assert!(addr == @my_addrx, 0);
    }

    /// Asserts that a user does not already have a vesting stream.
    /// Ensures uniqueness for vesting streams per beneficiary.
    public fun assert_user_not_exists(streams: &Table<address, VestingStream>, beneficiary: address) {
        assert!(!table::contains(streams, beneficiary), 1);
    }

    /// Initializes the contract and sets up the data structure to hold vesting streams.
    /// Only the owner can initialize the contract
    public fun initialize(account: &signer) {
        let addr = signer::address_of(account);
        assert_is_owner(addr);

        let vesting_data = VestingStreams {
            streams: table::new<address, VestingStream>(),
        };
        move_to(account, vesting_data);
    }

    /// Adds a new vesting stream for a specified beneficiary.
    /// Only the owner can add users, and the `total_amount` must be greater than zero.
    public fun add_user (
        account: &signer,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64
    ) acquires VestingStreams {
        let addr = signer::address_of(account);
        assert_is_owner(addr);

        let vesting_data = borrow_global_mut<VestingStreams>(addr);

        // Assert the user does not already exist
        assert_user_not_exists(&vesting_data.streams, beneficiary);

        // Ensure total_amount is greater than 0
        assert!(total_amount > 0, 3);

        // Create the vesting stream
        let vesting_stream = VestingStream {
            beneficiary,
            total_amount,
            start_time,
            cliff,
            duration,
            claimed_amount: 0,
        };

        // Add the vesting stream to the table
        table::add(&mut vesting_data.streams, beneficiary, vesting_stream);
    }

    /// Checks the claimable amount for a beneficiary based on the current time.
    /// This considers the vesting schedule, cliff, and already claimed amount.
    public fun check_claimable_amount(
        account: &signer,
        beneficiary: address,
        current_time: u64
    ) :u64 acquires VestingStreams  {
        let addr = signer::address_of(account);

        // Retrieve the vesting stream
        let vesting_data = borrow_global<VestingStreams>(addr);
        let stream = table::borrow(&vesting_data.streams, beneficiary);

        // If the current time is before the cliff, nothing is claimable
        if (current_time < stream.cliff) {
            return 0
        };

        // Calculate vested amount
        let vested_amount = if (current_time >= stream.duration) {
            stream.total_amount
        } else {
            (stream.total_amount * (current_time - stream.start_time)) / (stream.duration - stream.start_time)
        };

        // Calculate claimable amount
        let claimable_amount = vested_amount - stream.claimed_amount;
        return claimable_amount
    }

    /// Allows a user to claim a specific amount of vested tokens.
    /// Only the owner can update the VestingStreams storage.
    /// Ensures the claim is within the allowable range and updates the claimed amount.
    /// If all tokens are claimed, the vesting stream is removed.
    public fun claim_tokens(
        account: &signer,
        beneficiary: address,
        claim_amount: u64,
        current_time: u64
    ) acquires VestingStreams {
        let addr = signer::address_of(account);
        assert_is_owner(addr);

        // Retrieve the vesting stream
        let vesting_data = borrow_global_mut<VestingStreams>(addr);
        let stream = table::borrow_mut(&mut vesting_data.streams, beneficiary);

        // Calculate vested amount
        let vested_amount = if (current_time >= stream.duration) {
            stream.total_amount
        } else {
            (stream.total_amount * (current_time - stream.start_time)) / (stream.duration - stream.start_time)
        };

        let claimable_amount = vested_amount - stream.claimed_amount;

        // Ensure there is a vested amount available
        assert!(vested_amount > 0, 2); // No vested tokens to claim
        assert!(claim_amount > 0, 4); // Claim amount must be greater than zero
        assert!(claim_amount <= claimable_amount, 5); // Cannot claim more than claimable tokens

        // Update the claimed amount
        stream.claimed_amount = stream.claimed_amount + claim_amount;

        // Remove the stream if all tokens are claimed
        if (stream.claimed_amount == stream.total_amount) {
            table::remove(&mut vesting_data.streams, beneficiary);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// TESTS
    ////////////////////////////////////////////////////////////////
    

    /// Test to validate the claimable amount calculation.
    /// Includes scenarios for before cliff, after cliff, and at vesting completion.
    #[test(admin = @my_addrx, aptos_framework = @0x1)]
    public fun test_check_claimable_amount(admin: signer, aptos_framework: &signer) acquires VestingStreams {

    // Set up global time for testing purpose
    timestamp::set_time_has_started_for_testing(aptos_framework);

    // Initialize the contract
    initialize(&admin);

    // Add a user with a vesting stream
    let beneficiary = @0x1;
    let total_amount = 1000;
    let start_time = timestamp::now_seconds();
    let cliff = start_time + 60 * 60 * 24 * 30 * 2;
    let duration = start_time + 60 * 60 * 24 * 30 * 4; 

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );

    // Simulate checking claimable amount before the cliff
    let current_time = start_time + 60 * 60 * 24 * 30; // 1 month (before cliff)
    let claimable_before_cliff = check_claimable_amount(&admin, beneficiary, current_time);
    debug::print(&string::utf8(b"Claimable amount before cliff: ",));
    debug::print(&claimable_before_cliff);
    assert!(claimable_before_cliff == 0, 0); // Nothing claimable before the cliff

    // Simulate checking claimable amount after 3 months (1 month after cliff)
    let current_time_after_cliff = start_time + 60 * 60 * 24 * 30 * 3; // 3 months
    let claimable_after_cliff = check_claimable_amount(&admin, beneficiary, current_time_after_cliff);
    let expected_claimable_after_cliff = (total_amount * (current_time_after_cliff - start_time)) / (4 * 60 * 60 * 24 * 30);
    debug::print(&string::utf8(b"Claimable amount after 3 months, 1 month after cliff: ",));
    debug::print(&expected_claimable_after_cliff);
    assert!(claimable_after_cliff == expected_claimable_after_cliff, 0);

    // Simulate checking claimable amount at the end of vesting duration
    let current_time_end = start_time + 60 * 60 * 24 * 30 * 4; // 4 months
    let claimable_at_end = check_claimable_amount(&admin, beneficiary, current_time_end);
    debug::print(&string::utf8(b"Claimable amount at the end of vesting duration: ",));
    debug::print(&claimable_at_end);
    assert!(claimable_at_end == total_amount, 0); // All tokens should be claimable
    }


    ////////////////////////////////////////////////////////////////
    /// Test to validate that only the owner can initialize the contract.
    /// Attempts to initialize the contract as a non-owner and expects a failure.
    #[test(beneficiary = @0x1)]
    #[expected_failure]
    public fun test_initialise_by_beneficiary(beneficiary: signer)  {
    // Attempt to initialize the contract as the beneficiary
    //This should throw an error as the contract can be initialized only by the owner
    initialize(&beneficiary); 
    }

    ////////////////////////////////////////////////////////////////
    /// Test to validate that adding the same beneficiary twice fails.
    /// Verifies that the contract prevents duplicate vesting streams for the same beneficiary. 
    #[test(admin = @my_addrx, aptos_framework = @0x1)]
    #[expected_failure]
    public fun test_add_thesame_beneficiary_twice(admin: signer, aptos_framework: &signer) acquires VestingStreams{
    
    initialize(&admin); 

     // Set up global time for testing purpose
    timestamp::set_time_has_started_for_testing(aptos_framework);
    // Initialize the contract
    initialize(&admin);
    // Add a user with a vesting stream
    let beneficiary = @0x1;
    let total_amount = 1000;
    let start_time = timestamp::now_seconds();
    let cliff = start_time + 60 * 60 * 24 * 30 * 2;
    let duration = start_time + 60 * 60 * 24 * 30 * 4; 

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );
    }


    ////////////////////////////////////////////////////////////////
    // Test to ensure that beneficiaries cannot modify vesting streams
    #[test(admin = @my_addrx, beneficiaryTest = @0x4, aptos_framework = @0x1)]
    #[expected_failure]
    public fun test_modify_by_beneficiary(admin: signer, beneficiaryTest: signer, aptos_framework: &signer) acquires VestingStreams {
    // Set up global time for testing purpose
    timestamp::set_time_has_started_for_testing(aptos_framework);

    // Initialize the contract
    initialize(&admin);

    // Add a user with a vesting stream
    let beneficiary = @0x1;
    let total_amount = 1000;
    let start_time = timestamp::now_seconds();
    let cliff = start_time + 60 * 60 * 24 * 30 * 2;
    let duration = start_time + 60 * 60 * 24 * 30 * 4;

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );

    // Simulate after 2 months + 1 sec (right after the cliff time)
    let current_time1 = start_time + 60 * 60 * 24 * 30 * 2 + 1;
    let claim_amount1 = 300;

    let claimable_at_end1 = check_claimable_amount(&admin, beneficiary, current_time1);
    debug::print(&string::utf8(b"Claimable amount after cliff: "));
    debug::print(&claimable_at_end1);

    // Attempt to claim tokens as a non-owner (expected to fail)
    claim_tokens(&beneficiaryTest, beneficiary, claim_amount1, current_time1); // This should fail
    }


    ////////////////////////////////////////////////////////////////
    // Test to ensure claiming works correctly and excessive claims are rejected
    #[test(admin = @my_addrx, aptos_framework = @0x1)]
    #[expected_failure]
    public fun test_claim_tokens(admin: signer, aptos_framework: &signer) acquires VestingStreams {
    // Set up global time for testing purpose
    timestamp::set_time_has_started_for_testing(aptos_framework);

    // Initialize the contract
    initialize(&admin);

    // Add a user with a vesting stream
    let beneficiary = @0x1;
    let total_amount = 1000;
    let start_time = timestamp::now_seconds();
    let cliff = start_time + 60 * 60 * 24 * 30 * 2;
    let duration = start_time + 60 * 60 * 24 * 30 * 4; 

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );

    // Simulate after 2 months + 1 sec (right after the cliff time)
    let current_time1 = start_time + 60 * 60 * 24 * 30 * 2 + 1;
    let claim_amount1 = 300;

    let claimable_at_end1 = check_claimable_amount(&admin, beneficiary, current_time1);
    debug::print(&string::utf8(b"Claimable amount after cliff: "));
    debug::print(&claimable_at_end1);

    // Claim tokens
    claim_tokens(&admin, beneficiary, claim_amount1, current_time1);

    // Verify the claimed amount
    let vesting_data = borrow_global<VestingStreams>(@my_addrx);
    let stream = table::borrow(&vesting_data.streams, beneficiary);
    debug::print(&string::utf8(b"Claimed Amount: "));
    debug::print(&stream.claimed_amount);
    assert!(stream.claimed_amount == claim_amount1, 0);

    // Simulate claiming excessive tokens before 3 months (Max claimable token is 500)
    let current_time2 = start_time + 60 * 60 * 24 * 30 * 2 + 20; // 2 months + 20 seconds
    let claim_amount2 = 600; // This exceeds the maximum claimable amount

    let claimable_at_end2 = check_claimable_amount(&admin, beneficiary, current_time2);
    debug::print(&string::utf8(b"Claimable amount before 3 months: "));
    debug::print(&claimable_at_end2);

    // Expect an error due to excessive claim
    claim_tokens(&admin, beneficiary, claim_amount2, current_time2); // Attempt to claim tokens
  
    // Verify the claimed amount remains unchanged
    let vesting_data = borrow_global<VestingStreams>(@my_addrx);
    let stream = table::borrow(&vesting_data.streams, beneficiary);
    debug::print(&string::utf8(b"Claimed Amount after excessive claim attempt: "));
    debug::print(&stream.claimed_amount);
    assert!(stream.claimed_amount == claim_amount1, 0); // Claimed amount should still be 300
    }


    ////////////////////////////////////////////////////////////////
    // Test to ensure all tokens can be claimed at the end of the vesting period
    #[test(admin = @my_addrx, aptos_framework = @0x1)]
    public fun test_all_tokens_claimed(admin: signer, aptos_framework: &signer) acquires VestingStreams {
    // Set up global time for testing purpose
    timestamp::set_time_has_started_for_testing(aptos_framework);

    // Initialize the contract
    initialize(&admin);

    // Add a user with a vesting stream
    let beneficiary = @0x2;
    let total_amount = 1000;
    let start_time = timestamp::now_seconds();
    let cliff = start_time + 60 * 60 * 24 * 30 * 2; // 2 months
    let duration = start_time + 60 * 60 * 24 * 30 * 4; // 4 months

    add_user(
        &admin,
        beneficiary,
        total_amount,
        start_time,
        cliff,
        duration,
    );

    // Simulate claiming all tokens after the vesting duration
    let current_time = start_time + 60 * 60 * 24 * 30 * 4; // End of duration
    let claim_amount = total_amount;

    // Check claimable amount before claiming
    let claimable_before = check_claimable_amount(&admin, beneficiary, current_time);
    debug::print(&string::utf8(b"Claimable amount before claiming all tokens: "));
    debug::print(&claimable_before);
    assert!(claimable_before == total_amount, 0); // Ensure all tokens are claimable

    // Claim all tokens
    claim_tokens(&admin, beneficiary, claim_amount, current_time);

    // Verify the user has been removed from the vesting streams
    let vesting_data = borrow_global<VestingStreams>(@my_addrx);
    assert!(table::contains(&vesting_data.streams, beneficiary) == false, 0); // User should be removed
}


}