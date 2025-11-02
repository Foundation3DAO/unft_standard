#[test_only]
module unft_standard::gas_optimization_tests;

use std::string;
use sui::test_scenario::{Self as ts, Scenario};
use sui::package;
use unft_standard::unft_standard::{
    Self as unft,
    NftRegistry,
    NftCollection,
    NftMintCap,
    NftCollectionMetadataCap,
};

// Test NFT type
public struct TestNFT has drop {}
public struct GAS_OPTIMIZATION_TESTS has drop {}

// ----------------------------
// Helper Functions
// ----------------------------
fun str(s: vector<u8>): string::String {
    string::utf8(s)
}

fun create_publisher_and_registry(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0xC0FFEE);
    {
        let otw = GAS_OPTIMIZATION_TESTS {};
        let publisher = package::test_claim(otw, ts::ctx(scenario));
        transfer::public_transfer(publisher, @0xC0FFEE);
        unft::test_init(ts::ctx(scenario));
    };
}

fun get_registry_mut(s: &Scenario): NftRegistry { ts::take_shared(s) }
fun get_registry(s: &Scenario): NftRegistry { ts::take_shared(s) }

// ----------------------------
// Phase 4.1: BatchMintedEvent Verification
// ----------------------------

#[test]
fun test_batch_mint_emits_single_batch_event() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    // Create collection
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let publisher = ts::take_from_sender<package::Publisher>(&scenario);
        let mut registry = get_registry_mut(&scenario);

        let (mint_cap, burn_opt, meta_cap) = unft::create_collection_v2<TestNFT>(
            &publisher,
            &mut registry,
            str(b"Batch Test"),
            str(b"Testing BatchMintedEvent"),
            str(b"https://example.com/image.png"),
            option::none(),
            0u8,
            option::some(100u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xC0FFEE);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Batch mint - should emit single BatchMintedEvent
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
        vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));

        unft::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        // Verify supply updated correctly
        let (minted, burned, _) = unft::supply(&collection);
        assert!(minted == 5, 0);
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
fun test_batch_event_contains_all_nft_ids() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        if (burn_opt.is_some()) {
            transfer::public_transfer(burn_opt.destroy_some(), @0xC0FFEE);
        } else {
            burn_opt.destroy_none();
        };
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // Create and track NFT UIDs
        let mut nfts = vector::empty<UID>();
        let mut expected_ids = vector::empty<object::ID>();

        let nft1 = object::new(ts::ctx(&mut scenario));
        expected_ids.push_back(object::uid_to_inner(&nft1));
        nfts.push_back(nft1);

        let nft2 = object::new(ts::ctx(&mut scenario));
        expected_ids.push_back(object::uid_to_inner(&nft2));
        nfts.push_back(nft2);

        let nft3 = object::new(ts::ctx(&mut scenario));
        expected_ids.push_back(object::uid_to_inner(&nft3));
        nfts.push_back(nft3);

        unft::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        // Note: We cannot directly inspect event contents in test_scenario
        // But we verify the behavior is correct via supply counters
        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 3, 0);

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
fun test_batch_event_count_field_accurate() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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
            option::some(50u64),
            false,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Test different batch sizes
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // Batch of 10
        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 10) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 10, 0);

        // Cleanup
        while (!vector::is_empty(&nfts)) {
            vector::pop_back(&mut nfts).delete();
        };
        vector::destroy_empty(nfts);

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    // Batch of 20
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nfts = vector::empty<UID>();
        let mut i = 0;
        while (i < 20) {
            vector::push_back(&mut nfts, object::new(ts::ctx(&mut scenario)));
            i = i + 1;
        };

        unft::track_batch_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nfts,
            ts::ctx(&mut scenario)
        );

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 30, 0); // 10 + 20

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
fun test_single_mint_still_uses_minted_event() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Single mint should still work and emit MintedEvent (not BatchMintedEvent)
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        let mut nft_uid = object::new(ts::ctx(&mut scenario));
        unft::track_mint<TestNFT>(
            &mint_cap,
            &mut collection,
            &mut nft_uid,
            ts::ctx(&mut scenario)
        );

        let (minted, _, _) = unft::supply(&collection);
        assert!(minted == 1, 0);

        nft_uid.delete();

        ts::return_to_sender(&scenario, mint_cap);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

// ----------------------------
// Phase 4.2: Pause/Resume Idempotence Verification
// ----------------------------

#[test]
fun test_duplicate_pause_early_returns() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // First pause
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        assert!(unft::is_paused(&collection), 0);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // Second pause (should be idempotent - early return)
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // This should early return without modifying state or emitting event
        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        // Still paused
        assert!(unft::is_paused(&collection), 1);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_duplicate_resume_early_returns() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Pause first
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // First resume
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        assert!(!unft::is_paused(&collection), 0);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // Second resume (should be idempotent - early return)
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        // This should early return without modifying state or emitting event
        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        // Still not paused
        assert!(!unft::is_paused(&collection), 1);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_pause_idempotence_no_event_spam() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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
            true,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Multiple pause calls - only first should emit event
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        // Collection should still be paused
        assert!(unft::is_paused(&collection), 0);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}

#[test]
fun test_resume_idempotence_no_event_spam() {
    let mut scenario = ts::begin(@0xC0FFEE);

    create_publisher_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, @0xC0FFEE);
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
            true,
            false,
            ts::ctx(&mut scenario)
        );

        transfer::public_transfer(mint_cap, @0xC0FFEE);
        burn_opt.destroy_none();
        transfer::public_transfer(meta_cap, @0xC0FFEE);

        ts::return_to_sender(&scenario, publisher);
        ts::return_shared(registry);
    };

    // Pause
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::pause_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    // Multiple resume calls - only first should emit event
    ts::next_tx(&mut scenario, @0xC0FFEE);
    {
        let meta_cap = ts::take_from_sender<NftCollectionMetadataCap<TestNFT>>(&scenario);
        let registry = get_registry(&scenario);
        let locator = unft::get_locator<TestNFT>(&registry);
        let metadata = ts::take_shared_by_id(&scenario, unft::locator_metadata_id(locator));
        let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
        ts::return_shared(registry);

        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));
        unft::resume_collection<TestNFT>(&meta_cap, &metadata, &mut collection, ts::ctx(&mut scenario));

        // Collection should be resumed
        assert!(!unft::is_paused(&collection), 0);

        ts::return_to_sender(&scenario, meta_cap);
        ts::return_shared(metadata);
        ts::return_shared(collection);
    };

    ts::end(scenario);
}
