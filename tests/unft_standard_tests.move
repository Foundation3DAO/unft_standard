#[test_only]
module unft_standard::unft_standard_tests;

use std::string::{Self, String};
use sui::test_scenario::{Self as ts, Scenario};
use sui::package;
use unft_standard::unft_standard::{
    Self,
    NftRegistry,
    NftCollection,
    NftCollectionMetadata,
    NftMintCap,
    NftBurnCap,
    NftCollectionMetadataCap,
};

// ----------------------------
// Test NFT Type (Witness Pattern)
// ----------------------------
// TestNFT is used as a phantom type parameter, doesn't need abilities
public struct TestNFT has drop {}
public struct UNFT_STANDARD_TESTS has drop {}

// ----------------------------
// Helper Functions
// ----------------------------
fun str(s: vector<u8>): String {
    string::utf8(s)
}

fun create_publisher_and_registry(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0xABCD);
    {
        // Create publisher
        let otw = UNFT_STANDARD_TESTS {};
        let publisher = package::test_claim(otw, ts::ctx(scenario));
        transfer::public_transfer(publisher, @0xABCD);

        // Create registry (since init won't run in tests)
        unft_standard::test_init(ts::ctx(scenario));
    };
}

fun get_registry_mut(scenario: &Scenario): NftRegistry {
    ts::take_shared(scenario)
}

fun get_registry(scenario: &Scenario): NftRegistry {
    // Registry is shared, not immutable
    ts::take_shared(scenario)
}

// ----------------------------
// Phase 1: Test Framework Setup
// ----------------------------

#[test]
fun test_framework_basic() {
    // Simple test to verify framework works
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::end(scenario);
}

// ----------------------------
// Phase 2: Basic Functionality Tests
// ----------------------------

// 2.1 Collection Creation Tests

#[test]
fun test_create_collection_with_max_supply() {
    let mut scenario = ts::begin(@0xABCD);

    // Create publisher
    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test Collection"),
            str(b"A test NFT collection"),
            str(b"https://example.com/image.png"),
            option::some(str(b"https://example.com")),
            0u8,
            option::some(1000u64),
            true,
            true,
            ts::ctx(&mut scenario)
        );

        // Verify collection is registered
        assert!(unft_standard::collection_exists<TestNFT>(&registry), 0);

        // Transfer capabilities
        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_create_unlimited_collection() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_unlimited_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Unbounded Collection"),
            str(b"No max supply"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            false,
            false,
            ts::ctx(&mut scenario)
        );

        // Verify collection exists
        assert!(unft_standard::collection_exists<TestNFT>(&registry), 0);

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_create_collection_duplicate_fails() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Create first collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"First"),
            str(b"First collection"),
            str(b"https://example.com/1.png"),
            option::none(),
            0u8,
            option::some(100u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Try to create duplicate - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Second"),
            str(b"Duplicate collection"),
            str(b"https://example.com/2.png"),
            option::none(),
            0u8,
            option::some(200u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

// 2.2 URL Validation Tests

#[test]
#[expected_failure]
fun test_empty_image_url_rejected() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b""), // Empty image URL - should fail
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_empty_external_url_rejected() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::some(str(b"")), // Empty external URL - should fail
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

// 2.3 Minting Tests

#[test]
fun test_register_single_mint() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Create collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(100u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint NFT
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        // Verify mint counter increased
        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 1, 0);
        assert!(burned == 0, 1);

        nft_uid.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_track_batch_mint() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Create collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(100u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Batch mint
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));

        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        // Verify mint counter
        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 3, 0);
        assert!(burned == 0, 1);

        // Cleanup
        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_batch_mint_empty_vector() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();

        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        let (minted, _burned, _) = unft_standard::supply(&collection);
        assert!(minted == 0, 0);

        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_mint_exceeds_max_supply_fails() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(2u64), // Max supply = 2
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint 3 NFTs (exceeds max supply of 2)
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));

        // This should fail
        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_mint_unbounded_supply() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_unlimited_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint many NFTs without limit
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 100) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        let (minted, _, _) = unft_standard::supply(&collection);
        assert!(minted == 100, 0);

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// 2.4 Pause/Resume Tests

#[test]
fun test_pause_resume_collection() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            true, // pausable
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Pause collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // Resume collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_pause_non_pausable_fails() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false, // NOT pausable
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Try to pause - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_mint_while_paused_fails() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            true, // pausable
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Pause collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // Try to mint while paused - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        nft_uid.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// 2.5 Burn Tests

#[test]
fun test_track_burn() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            true, // with burn cap
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint then burn
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let burn_cap = ts::take_from_sender<NftBurnCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        unft_standard::track_burn<TestNFT>(
            &burn_cap,
            &mut collection,
            nft_uid,
            ts::ctx(&mut scenario)
        );

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 1, 0);
        assert!(burned == 1, 1);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_to_sender(&scenario, burn_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_track_burn_by_owner() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false, // no burn cap
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint then burn by owner
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        unft_standard::track_burn_by_owner<TestNFT>(
            &mut collection,
            nft_uid,
            ts::ctx(&mut scenario)
        );

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 1, 0);
        assert!(burned == 1, 1);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_burn_does_not_affect_minted() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint, verify, burn, verify minted stays same
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        let (minted_before, _, _) = unft_standard::supply(&collection);
        assert!(minted_before == 1, 0);

        unft_standard::track_burn_by_owner<TestNFT>(
            &mut collection,
            nft_uid,
            ts::ctx(&mut scenario)
        );

        let (minted_after, burned, _) = unft_standard::supply(&collection);
        assert!(minted_after == 1, 1); // minted stays 1
        assert!(burned == 1, 2); // burned increases

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// 2.3 Burn Permission Tests

#[test]
#[expected_failure]
fun test_owner_burn_fails_when_burn_cap_exists() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Create collection with burn cap
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Burn Restricted"),
            str(b"Burn requires cap"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(10u64),
            false,
            true, // with burn cap
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        // keep burn cap with sender
        if (burn_opt.is_some()) { transfer::public_transfer(burn_opt.destroy_some(), @0xABCD); } else { burn_opt.destroy_none(); };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint then attempt owner burn (should fail)
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft_uid, ts::ctx(&mut scenario));

        // Owner burn should abort with EOwnerBurnDisabled = 13
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft_uid, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_burn_with_cap_succeeds_when_burn_cap_exists() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Create collection with burn cap
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Burn Restricted"),
            str(b"Burn requires cap"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(10u64),
            false,
            true, // with burn cap
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        if (burn_opt.is_some()) { transfer::public_transfer(burn_opt.destroy_some(), @0xABCD); } else { burn_opt.destroy_none(); };
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint then burn using cap
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let burn_cap = ts::take_from_sender<NftBurnCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft_uid, ts::ctx(&mut scenario));

        unft_standard::track_burn<TestNFT>(&burn_cap, &mut collection, nft_uid, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 1, 0);
        assert!(burned == 1, 1);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_to_sender(&scenario, burn_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// 2.6 Metadata Update Tests

#[test]
fun test_update_metadata_all_fields() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Old Name"),
            str(b"Old Desc"),
            str(b"https://old.com/image.png"),
            option::some(str(b"https://old.com")),
            0u8,
            option::some(100u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Update all fields
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft_standard::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"New Name")),
            option::some(str(b"New Desc")),
            option::some(str(b"https://new.com/image.png")),
            option::some(option::some(str(b"https://new.com"))),
            option::some(8u8),
            option::some(option::some(200u64)),
            ts::ctx(&mut scenario)
        );

        // Verify updates
        assert!(unft_standard::name(&metadata) == &str(b"New Name"), 0);
        assert!(unft_standard::description(&metadata) == &str(b"New Desc"), 1);
        assert!(unft_standard::image_url(&metadata) == &str(b"https://new.com/image.png"), 2);
        assert!(unft_standard::decimals(&metadata) == 8u8, 3);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
fun test_update_metadata_partial_fields() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Original"),
            str(b"Description"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Update only name
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft_standard::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"Updated Name")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft_standard::name(&metadata) == &str(b"Updated Name"), 0);
        assert!(unft_standard::description(&metadata) == &str(b"Description"), 1);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_update_metadata_validates_urls() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Try to update with empty image URL - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft_standard::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::some(str(b"")), // Empty - should fail
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 3: New Features Tests
// ----------------------------

// 3.1 Global Registry Tests

#[test]
fun test_registry_initialization() {
    let mut scenario = ts::begin(@0xABCD);
    create_publisher_and_registry(&mut scenario);

    // Registry is created in init, which is called automatically
    // Just verify it exists
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        // If we can access it, init worked
        assert!(true, 0);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_collection_exists_check() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // Check before creation
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        assert!(!unft_standard::collection_exists<TestNFT>(&registry), 0);
        ts::return_shared(registry);
    };

    // Create collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Check after creation
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        assert!(unft_standard::collection_exists<TestNFT>(&registry), 1);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_get_locator() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Borrow locator
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        let _locator = unft_standard::get_locator<TestNFT>(&registry);
        // If we can borrow it, test passes
        assert!(true, 0);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_get_locator_not_registered_fails() {
    let mut scenario = ts::begin(@0xABCD);
    create_publisher_and_registry(&mut scenario);

    // Try to borrow locator for non-existent collection - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        let _locator = unft_standard::get_locator<TestNFT>(&registry);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

// 3.2 Metadata Freezing Tests

#[test]
fun test_freeze_metadata() {
    let mut scenario = ts::begin(@0xABCD);
    create_publisher_and_registry(&mut scenario);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Freeze metadata
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        assert!(!unft_standard::metadata_frozen(&metadata), 0);

        unft_standard::freeze_metadata<TestNFT>(
            meta_cap,
            &mut metadata,
            ts::ctx(&mut scenario)
        );

        assert!(unft_standard::metadata_frozen(&metadata), 1);

        ts::return_shared(metadata);
        // Note: meta_cap is consumed by freeze_metadata
    };

    ts::end(scenario);
}

// Note: test_update_frozen_metadata_fails is not possible to implement
// because freeze_metadata() consumes the metadata cap, making it impossible
// to call update_metadata() afterwards. The EMetadataFrozen check provides
// defense-in-depth but cannot be tested through the public API.

// 3.3 Supply Finalization Tests

#[test]
fun test_finalize_supply() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_unlimited_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint some NFTs
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 10) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Finalize supply
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::finalize_supply<TestNFT>(
            mint_cap,
            &mut collection,
            ts::ctx(&mut scenario)
        );

        let (minted, _, max_supply) = unft_standard::supply(&collection);
        assert!(max_supply.is_some(), 0);
        assert!(*max_supply.borrow() == minted, 1);
        assert!(minted == 10, 2);

        ts::return_shared(collection);
        // Note: mint_cap is consumed
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_finalize_already_fixed_supply_fails() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(100u64), // Already has max_supply
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Try to finalize - should fail
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::finalize_supply<TestNFT>(
            mint_cap,
            &mut collection,
            ts::ctx(&mut scenario)
        );

        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_finalize_with_zero_minted() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_unlimited_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Finalize without minting anything
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        // This should abort with ECannotFinalizeZeroSupply
        // because no NFTs have been minted yet
        unft_standard::finalize_supply<TestNFT>(
            mint_cap,
            &mut collection,
            ts::ctx(&mut scenario)
        );

        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// 3.4 Version and Reserved Field Tests

#[test]
fun test_version_field_initialized_to_one() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Check version
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        assert!(unft_standard::version(&metadata) == 1u8, 0);

        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 4: Integration and Lifecycle Tests
// ----------------------------

#[test]
fun test_complete_collection_lifecycle() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // 1. Create collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Lifecycle Test"),
            str(b"Complete lifecycle"),
            str(b"https://example.com/image.png"),
            option::some(str(b"https://example.com")),
            0u8,
            option::some(100u64),
            true, // pausable
            true, // with burn cap
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        transfer::public_transfer(burn_opt.destroy_some(), @0xABCD);
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // 2. Mint some NFTs
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 5) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft_standard::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        // Clean up all NFTs (UID doesn't have key ability, can't transfer)
        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // 3. Update metadata
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft_standard::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"Updated Name")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    // 4. Pause collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // 5. Resume collection
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        unft_standard::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // 6. Mint and burn an NFT to test burn functionality
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let burn_cap = ts::take_from_sender<NftBurnCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        // Mint one more NFT
        let mut new_nft = object::new(ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut new_nft,
            ts::ctx(&mut scenario)
        );

        // Immediately burn it (UID can't be transferred, so we burn inline)
        unft_standard::track_burn<TestNFT>(
            &burn_cap,
            &mut collection,
            new_nft,
            ts::ctx(&mut scenario)
        );

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 6, 0); // 5 from step 2 + 1 new = 6
        assert!(burned == 1, 1); // 1 burned

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_to_sender(&scenario, burn_cap);
        ts::return_shared(collection);
    };

    // 7. Verify final state
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        assert!(unft_standard::collection_exists<TestNFT>(&registry), 0);

        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        let collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        assert!(unft_standard::name(&metadata) == &str(b"Updated Name"), 1);

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 6, 2); // 5 from step 2 + 1 from step 6 = 6
        assert!(burned == 1, 3); // 1 burned in step 6

        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_supply_tracking_with_multiple_operations() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint, burn, mint, burn - verify counts
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft_standard::locator_collection_id(locator));
        ts::return_shared(registry);

        // Mint 3
        let mut nft1 = object::new(ts::ctx(&mut scenario));
        let mut nft2 = object::new(ts::ctx(&mut scenario));
        let mut nft3 = object::new(ts::ctx(&mut scenario));

        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft1, ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft2, ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft3, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 3, 0);
        assert!(burned == 0, 1);

        // Burn 1
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft1, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 3, 2); // minted doesn't decrease
        assert!(burned == 1, 3);

        // Mint 2 more
        let mut nft4 = object::new(ts::ctx(&mut scenario));
        let mut nft5 = object::new(ts::ctx(&mut scenario));

        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft4, ts::ctx(&mut scenario));
        unft_standard::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft5, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 5, 4);
        assert!(burned == 1, 5);

        // Burn all remaining
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft2, ts::ctx(&mut scenario));
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft3, ts::ctx(&mut scenario));
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft4, ts::ctx(&mut scenario));
        unft_standard::track_burn_by_owner<TestNFT>(&mut collection, nft5, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft_standard::supply(&collection);
        assert!(minted == 5, 6); // still 5
        assert!(burned == 5, 7); // all burned

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// ----------------------------
// Test for clearing external_url (P2 fix validation)
// ----------------------------

#[test]
fun test_clear_external_url() {
    let mut scenario = ts::begin(@0xABCD);

    create_publisher_and_registry(&mut scenario);

    // 1. Create collection with external_url
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft_standard::create_collection<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::some(str(b"https://example.com")),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xABCD);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xABCD);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // 2. Verify external_url is set
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        assert!(unft_standard::external_url(&metadata).is_some(), 0);
        assert!(unft_standard::external_url(&metadata).borrow() == &str(b"https://example.com"), 1);

        ts::return_shared(metadata);
    };

    // 3. Clear external_url by passing some(none())
    ts::next_tx(&mut scenario, @0xABCD);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft_standard::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft_standard::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft_standard::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::none(),
            option::some(option::none()),  // Clear external_url
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        // Verify external_url is cleared
        assert!(unft_standard::external_url(&metadata).is_none(), 2);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}
