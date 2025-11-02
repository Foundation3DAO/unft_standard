#[test_only]
module unft_standard::edge_case_tests;

use std::string;
use sui::test_scenario::{Self as ts, Scenario};
use sui::package;
use unft_standard::unft_standard::{
    Self as unft,
    NftRegistry,
    NftCollection,
    NftCollectionMetadata,
    NftMintCap,
    NftCollectionMetadataCap,
};

// Test NFT type
public struct TestNFT has drop {}
public struct EDGE_CASE_TESTS has drop {}

// Helper functions
fun str(s: vector<u8>): string::String { string::utf8(s) }

fun create_publisher_and_registry(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0xED6E);
    {
        let otw = EDGE_CASE_TESTS {};
        let publisher = package::test_claim(otw, ts::ctx(scenario));
        transfer::public_transfer(publisher, @0xED6E);
        unft::test_init(ts::ctx(scenario));
    };
}

fun get_registry_mut(s: &Scenario): NftRegistry { ts::take_shared(s) }
fun get_registry(s: &Scenario): NftRegistry { ts::take_shared(s) }

// ----------------------------
// Phase 1.1: Numeric Boundaries
// ----------------------------

#[test]
fun test_max_supply_u64_max() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        // Create collection with max_supply = u64::MAX
        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Max Supply Test"),
            str(b"Test u64::MAX"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(18446744073709551615u64), // u64::MAX
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Verify max_supply is set correctly
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let (minted, burned, max_supply) = unft::supply(&collection);
        assert!(minted == 0, 0);
        assert!(burned == 0, 1);
        assert!(max_supply.is_some(), 2);
        assert!(*max_supply.borrow() == 18446744073709551615u64, 3);

        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_max_supply_equals_one() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        // Minimum meaningful max_supply
        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Single Supply"),
            str(b"Only one NFT allowed"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(1u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint exactly one
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft_uid, ts::ctx(&mut scenario));

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 1, 0);

        nft_uid.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_batch_mint_at_exact_boundary() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Boundary Test"),
            str(b"Test exact boundary"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(10u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Batch mint exactly to max_supply
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 10) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        let (minted, _, max_supply) = unft::supply(&collection);
        assert!(minted == 10, 0);
        assert!(minted == *max_supply.borrow(), 1);

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
#[expected_failure]
fun test_mint_exceeds_by_one() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(5u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // Try to mint 6 (exceeds by 1)
        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 6) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 1.2: Zero/Empty Value Handling
// ----------------------------

#[test]
fun test_zero_decimals_allowed() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        // decimals=0 should be allowed
        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Zero Decimals"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8, // decimals = 0
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft::locator_metadata_id(locator));
        ts::return_shared(registry);

        assert!(unft::decimals(&metadata) == 0, 0);

        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
fun test_empty_batch_mint_early_return() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
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

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();

        // Empty batch should early return
        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 0, 0);

        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_single_item_batch_vs_single_mint() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
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

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Single mint via track_mint
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft_uid, ts::ctx(&mut scenario));

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 1, 0);

        nft_uid.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Batch mint with single item
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));

        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 2, 0); // Should be 2 now

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 1.3: State Transition Boundaries
// ----------------------------

#[test]
fun test_pause_resume_pause_cycle() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
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

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Cycle through pause/resume multiple times
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // Initial state: not paused
        assert!(!unft::is_paused(&collection), 0);

        // Pause -> Resume -> Pause -> Resume
        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        assert!(unft::is_paused(&collection), 1);

        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        assert!(!unft::is_paused(&collection), 2);

        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        assert!(unft::is_paused(&collection), 3);

        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        assert!(!unft::is_paused(&collection), 4);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 1.4: Metadata Edge Cases
// ----------------------------

#[test]
fun test_url_unicode_characters() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        // Unicode in URLs
        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"\xE4\xB8\xAD\xE6\x96\x87\xE5\x90\x8D\xE5\xAD\x97"), // "中文名字" in UTF-8
            str(b"Test unicode"),
            str(b"https://example.com/\xE4\xB8\xAD\xE6\x96\x87.png"),
            option::some(str(b"https://example.com/\xE4\xB8\xAD\xE6\x96\x87")),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_update_all_fields_sequentially() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Original"),
            str(b"Original"),
            str(b"https://original.com/image.png"),
            option::some(str(b"https://original.com")),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Update each field one by one
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft::locator_metadata_id(locator));
        ts::return_shared(registry);

        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"Name1")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::some(str(b"Desc1")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::some(str(b"https://new.com/image.png")),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::name(&metadata) == &str(b"Name1"), 0);
        assert!(unft::description(&metadata) == &str(b"Desc1"), 1);
        assert!(unft::image_url(&metadata) == &str(b"https://new.com/image.png"), 2);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
fun test_update_same_field_twice_in_sequence() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Original"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::none(),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft::locator_metadata_id(locator));
        ts::return_shared(registry);

        // Update name field multiple times
        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"First")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::name(&metadata) == &str(b"First"), 0);

        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"Second")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::name(&metadata) == &str(b"Second"), 1);

        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::some(str(b"Third")),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::name(&metadata) == &str(b"Third"), 2);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
fun test_max_supply_hint_larger_than_max_supply() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        // This is allowed but discouraged: hint > actual max
        // max_supply_hint is purely informational
        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(100u64), // max_supply = 100
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Update max_supply_hint to be larger than max_supply
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft::locator_metadata_id(locator));
        ts::return_shared(registry);

        // This should be allowed (hint is non-enforced)
        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(option::some(1000u64)), // hint = 1000 > max_supply = 100
            ts::ctx(&mut scenario)
        );

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

#[test]
fun test_clear_and_reset_external_url() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
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

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut metadata = ts::take_shared_by_id<NftCollectionMetadata<TestNFT>>(&scenario, unft::locator_metadata_id(locator));
        ts::return_shared(registry);

        // Clear
        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::none(),
            option::some(option::none()),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::external_url(&metadata).is_none(), 0);

        // Set again
        unft::update_metadata<TestNFT>(
            &meta_cap,
            &mut metadata,
            option::none(),
            option::none(),
            option::none(),
            option::some(option::some(str(b"https://new.com"))),
            option::none(),
            option::none(),
            ts::ctx(&mut scenario)
        );

        assert!(unft::external_url(&metadata).is_some(), 1);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 1.5: Supply Management Edge Cases
// ----------------------------

#[test]
fun test_burn_all_circulating_then_mint_more() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(10u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint 3
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft1 = object::new(ts::ctx(&mut scenario));
        let mut nft2 = object::new(ts::ctx(&mut scenario));
        let mut nft3 = object::new(ts::ctx(&mut scenario));

        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft1, ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft2, ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft3, ts::ctx(&mut scenario));

        // Burn all
        unft::track_burn_by_owner<TestNFT>(&mut collection, nft1, ts::ctx(&mut scenario));
        unft::track_burn_by_owner<TestNFT>(&mut collection, nft2, ts::ctx(&mut scenario));
        unft::track_burn_by_owner<TestNFT>(&mut collection, nft3, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft::supply(&collection);
        assert!(minted == 3, 0);
        assert!(burned == 3, 1);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Mint more after burning all
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft4 = object::new(ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft4, ts::ctx(&mut scenario));

        let (minted, burned, _) = unft::supply(&collection);
        assert!(minted == 4, 2); // minted keeps increasing
        assert!(burned == 3, 3);

        nft4.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_finalize_at_different_minted_counts() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_unlimited_collection_v2<TestNFT>(
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

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Mint exactly 7
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 7) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Finalize at 7
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::finalize_supply<TestNFT>(mint_cap, &mut collection, ts::ctx(&mut scenario));

        let (minted, _, max_supply) = unft::supply(&collection);
        assert!(minted == 7, 0);
        assert!(max_supply.is_some(), 1);
        assert!(*max_supply.borrow() == 7, 2);

        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_remaining_supply_edge_cases() {
    let mut scenario = ts::begin(@0xED6E);

    create_publisher_and_registry(&mut scenario);

    // Test with max_supply = 5
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Test"),
            str(b"Test"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(5u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xED6E);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xED6E);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Check remaining at various points
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // Initially: remaining = 5
        let remaining = unft::remaining_supply(&collection);
        assert!(remaining.is_some(), 0);
        assert!(*remaining.borrow() == 5, 1);

        ts::return_shared(collection);
    };

    // Mint 4
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 4) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(&mint_cap, &mut collection, &mut nfts, ts::ctx(&mut scenario));

        // After minting 4: remaining = 1
        let remaining = unft::remaining_supply(&collection);
        assert!(remaining.is_some(), 2);
        assert!(*remaining.borrow() == 1, 3);

        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Mint 1 more (reach max)
    ts::next_tx(&mut scenario, @0xED6E);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft = object::new(ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft, ts::ctx(&mut scenario));

        // After minting 5 (max): remaining = 0
        let remaining = unft::remaining_supply(&collection);
        assert!(remaining.is_some(), 4);
        assert!(*remaining.borrow() == 0, 5);

        nft.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}
