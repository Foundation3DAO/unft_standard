#[test_only]
module unft_standard::unft_discoverability_tests {
    use sui::package;
    use sui::test_scenario::{Self as ts, Scenario};
    use unft_standard::unft_standard::{
        Self as unft,
        NftCollection,
        NftMintCap,
    };

    // Phantom type for tests
    public struct TestNFT has drop {}
    public struct UNFT_STANDARD_DISC_TESTS has drop {}

    fun create_publisher_and_registry(scenario: &mut Scenario) {
        ts::next_tx(scenario, @0xC0FFEE);
        {
            let otw = UNFT_STANDARD_DISC_TESTS {};
            let publisher = package::test_claim(otw, ts::ctx(scenario));
            transfer::public_transfer(publisher, @0xC0FFEE);

            // Initialize registry shared object
            unft::test_init(ts::ctx(scenario));
        };
    }

    fun get_registry_mut(s: &Scenario): unft::NftRegistry { ts::take_shared(s) }
    fun get_registry(s: &Scenario): unft::NftRegistry { ts::take_shared(s) }

    #[test]
    fun test_get_and_try_get_collection_id() {
        let mut scenario = ts::begin(@0xC0FFEE);

        create_publisher_and_registry(&mut scenario);

        // tx: create collection and hand caps to sender
        ts::next_tx(&mut scenario, @0xC0FFEE);
        {
            let publisher = ts::take_from_sender<package::Publisher>(&scenario);
            let mut registry = get_registry_mut(&scenario);

            let (mint_cap, burn_opt, meta_cap) = unft::create_collection<TestNFT>(
                &publisher,
                &mut registry,
                b"Test Collection".to_string(),
                b"Discoverability".to_string(),
                b"https://example.com/image.png".to_string(),
                option::some(b"https://example.com".to_string()),
                0u8,
                option::some(100u64),
                false,
                false,
                ts::ctx(&mut scenario)
            );

            transfer::public_transfer(mint_cap, @0xC0FFEE);
            if (burn_opt.is_some()) { transfer::public_transfer(burn_opt.destroy_some(), @0xC0FFEE); } else { burn_opt.destroy_none(); };
            transfer::public_transfer(meta_cap, @0xC0FFEE);

            ts::return_to_sender(&scenario, publisher);
            ts::return_shared(registry);
        };

        // tx: mint one NFT (track_mint) then validate helpers
        ts::next_tx(&mut scenario, @0xC0FFEE);
        {
            let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
            let registry = get_registry(&scenario);
            let locator = unft::get_locator<TestNFT>(&registry);
            let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
            ts::return_shared(registry);

            let mut nft = object::new(ts::ctx(&mut scenario));
            unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft, ts::ctx(&mut scenario));

            // Strict get
            let cid_strict = unft::nft_collection_id(&nft);
            assert!(cid_strict == unft::locator_collection_id(locator), 0);

            // Try-get returns Some
            let cid_opt = unft::try_nft_collection_id(&nft);
            assert!(option::is_some(&cid_opt), 1);

            // Or-default returns actual ID, not fallback
            let fallback_uid = object::new(ts::ctx(&mut scenario));
            let fallback = object::uid_to_inner(&fallback_uid);
            let cid_default = unft::nft_collection_id_or(&nft, fallback);
            assert!(cid_default == unft::locator_collection_id(locator), 2);

            // has_collection_id true
            assert!(unft::has_collection_id(&nft), 3);

            // Cleanup
            nft.delete();
            fallback_uid.delete();
            ts::return_to_sender(&scenario, mint_cap);
            ts::return_shared(collection);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_missing_collection_id_paths() {
        let mut scenario = ts::begin(@0xC0FFEE);

        // Orphan UID (no dynamic field)
        ts::next_tx(&mut scenario, @0xC0FFEE);
        {
            let orphan = object::new(ts::ctx(&mut scenario));

            // try_get returns None
            let cid_opt = unft::try_nft_collection_id(&orphan);
            assert!(option::is_none(&cid_opt), 0);

            // has_collection_id false
            assert!(!unft::has_collection_id(&orphan), 1);

            // Or-default returns fallback
            let fb = object::new(ts::ctx(&mut scenario));
            let fb_id = object::uid_to_inner(&fb);
            let cid_default = unft::nft_collection_id_or(&orphan, fb_id);
            assert!(cid_default == fb_id, 2);

            // Cleanup
            orphan.delete();
            fb.delete();
        };

        ts::end(scenario);
    }

    #[test]
    fun test_batch_mixed_validity() {
        let mut scenario = ts::begin(@0xC0FFEE);

        create_publisher_and_registry(&mut scenario);

        // Create collection and caps
        ts::next_tx(&mut scenario, @0xC0FFEE);
        {
            let publisher = ts::take_from_sender<package::Publisher>(&scenario);
            let mut registry = get_registry_mut(&scenario);
            let (mint_cap, burn_opt, meta_cap) = unft::create_collection<TestNFT>(
                &publisher,
                &mut registry,
                b"Batch".to_string(),
                b"Mixed".to_string(),
                b"https://example.com/image.png".to_string(),
                option::none(),
                0u8,
                option::some(10u64),
                false,
                false,
                ts::ctx(&mut scenario)
            );
            transfer::public_transfer(mint_cap, @0xC0FFEE);
            if (burn_opt.is_some()) { transfer::public_transfer(burn_opt.destroy_some(), @0xC0FFEE); } else { burn_opt.destroy_none(); };
            transfer::public_transfer(meta_cap, @0xC0FFEE);
            ts::return_to_sender(&scenario, publisher);
            ts::return_shared(registry);
        };

        // Mint two, keep one orphan; validate batch on valid ones only
        ts::next_tx(&mut scenario, @0xC0FFEE);
        {
            let mint_cap = ts::take_from_sender<NftMintCap<TestNFT>>(&scenario);
            let registry = get_registry(&scenario);
            let locator = unft::get_locator<TestNFT>(&registry);
            let mut collection = ts::take_shared_by_id<NftCollection<TestNFT>>(&scenario, unft::locator_collection_id(locator));
            ts::return_shared(registry);

            let mut nft1 = object::new(ts::ctx(&mut scenario));
            let mut nft2 = object::new(ts::ctx(&mut scenario));
            let orphan = object::new(ts::ctx(&mut scenario));

            unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft1, ts::ctx(&mut scenario));
            unft::track_mint<TestNFT>(&mint_cap, &mut collection, &mut nft2, ts::ctx(&mut scenario));

            // Validate has_collection_id
            assert!(unft::has_collection_id(&nft1), 0);
            assert!(unft::has_collection_id(&nft2), 1);
            assert!(!unft::has_collection_id(&orphan), 2);

            // Batch only valid ones
            let mut ids = vector[nft1, nft2];
            let out = unft::nft_collection_ids(&ids);
            assert!(vector::length(&out) == 2, 3);
            assert!(*vector::borrow(&out, 0) == unft::locator_collection_id(locator), 4);

            // Cleanup UIDs
            while (!vector::is_empty(&ids)) { vector::pop_back(&mut ids).delete(); };
            vector::destroy_empty(ids);
            orphan.delete();

            ts::return_to_sender(&scenario, mint_cap);
            ts::return_shared(collection);
        };

        ts::end(scenario);
    }
}
