module unft_standard::unft_standard;

use std::string::String;
use sui::event;
use sui::dynamic_field;
use sui::package::Publisher;
use std::type_name;

// ----------------------------
// Error codes
// ----------------------------
#[error]
const ENotAuthorizedPublisher: vector<u8> =
    b"Only the publisher of this NFT type can perform this action";

#[error]
const EMaxSupplyExceeded: vector<u8> =
    b"Minting would exceed the collection's max supply";

#[error]
const EInvalidMintAmount: vector<u8> =
    b"Mint amount must be greater than 0";

#[error]
const EInvalidImageUrl: vector<u8> =
    b"Image URL must be a non-empty string";

#[error]
const EInvalidExternalUrl: vector<u8> =
    b"External URL must be a non-empty string";

#[error]
const ECollectionPaused: vector<u8> =
    b"Collection minting is currently paused";

#[error]
const ECollectionNotPausable: vector<u8> =
    b"This collection was not created with pausable = true";

#[error]
const EAlreadyRegistered: vector<u8> =
    b"A collection for this NFT type is already registered";

#[error]
const ENotRegistered: vector<u8> =
    b"No collection found for this NFT type in the registry";

#[error]
const EMetadataFrozen: vector<u8> =
    b"Metadata is frozen and cannot be updated";

#[error]
const EAlreadyFixedSupply: vector<u8> =
    b"Supply is already fixed at creation; cannot finalize again";

#[error]
const EMetadataCollectionMismatch: vector<u8> =
    b"NFT does not belong to this collection";

#[error]
const EOwnerBurnDisabled: vector<u8> =
    b"Owner burns are disabled; use BurnCap for centralized burn coordination";

#[error]
const ECannotFinalizeZeroSupply: vector<u8> =
    b"Cannot finalize supply with zero NFTs minted";

// ----------------------------
// Metadata field bitmask for MetadataUpdatedEvent.changed_fields
// ----------------------------
const FIELD_NAME: u8 = 1;           // 0b00000001
const FIELD_DESCRIPTION: u8 = 2;    // 0b00000010
const FIELD_IMAGE_URL: u8 = 4;      // 0b00000100
const FIELD_EXTERNAL_URL: u8 = 8;   // 0b00001000
const FIELD_DECIMALS: u8 = 16;      // 0b00010000
const FIELD_MAX_SUPPLY_HINT: u8 = 32; // 0b00100000

// ----------------------------
// Dynamic field key type
// ----------------------------
/// Key type for collection_id dynamic field to prevent cross-module conflicts.
///
/// **Note**: Using positional struct syntax for Move 2024 compliance.
/// Positional structs with no fields use `()` instead of `{}`.
public struct CollectionIdKey() has copy, drop, store;

// ----------------------------
// IPX-style collection capabilities
// ----------------------------
public struct NftMintCap<phantom T> has key, store { id: object::UID }
public struct NftBurnCap<phantom T> has key, store { id: object::UID }
public struct NftCollectionMetadataCap<phantom T> has key, store { id: object::UID }

// ----------------------------
// Collection singletons and supply ledger
// ----------------------------
public struct NftCollectionMetadata<phantom T> has key, store {
    id: object::UID,
    /// ID of the collection object this metadata belongs to.
    collection_id: object::ID,
    /// Schema / layout version of this metadata record.
    version: u8,
    /// Human-readable fields for wallets / explorers.
    name: String,
    description: String,
    image_url: String,
    external_url: option::Option<String>,
    /// Display hint for fractional quantity in some UIs. NFTs are non-fungible;
    /// defaults to 0 and does not affect uniqueness.
    decimals: u8,
    /// **UI/Marketing Hint (Non-Enforced)**: Optional supply target communicated to wallets,
    /// explorers, and marketplaces for display purposes. This value is NOT enforced on-chain
    /// and can be updated via `update_metadata` even after minting has started.
    ///
    /// **Economic Intent**: Allows creators to communicate scarcity expectations to buyers
    /// without locking themselves into a hard cap. Useful for:
    /// - Collections with uncertain demand
    /// - Phased launches (announce "up to 10,000" but may mint fewer)
    /// - Marketing flexibility (can adjust perceived rarity)
    ///
    /// **Important**: This is purely informational. For enforced caps, use `max_supply` in
    /// `NftCollection`. `None` indicates unlimited/unannounced supply.
    max_supply_hint: option::Option<u64>,
    /// If true, collection minting can be paused / resumed via {pause,resume}_collection.
    pausable: bool,
    /// Once set to true via `freeze_metadata`, subsequent updates are rejected.
    metadata_frozen: bool,
    /// Reserved for future extensibility (opaque bytes, not used by this version).
    reserved: vector<u8>,
}

public struct NftCollection<phantom T> has key, store {
    id: object::UID,
    metadata_id: object::ID, // Reference to NftCollectionMetadata
    /// **Enforced Supply Cap**: Hard limit on the number of NFTs that can be minted.
    /// Checked in `assert_can_mint` - minting fails with `EMaxSupplyExceeded` if
    /// `minted + amount > max_supply`.
    ///
    /// **Economic Intent**: Creates provable on-chain scarcity. Once set at collection
    /// creation, this value is immutable (except via `finalize_supply` which can only
    /// lower it to the current `minted` count). Guarantees to buyers:
    /// - Maximum circulating supply is cryptographically guaranteed
    /// - No unexpected inflation by creator
    /// - Scarcity is enforced by smart contract, not trust
    ///
    /// **Comparison with max_supply_hint**:
    /// - `max_supply` (here): Hard cap, enforced on-chain, immutable
    /// - `max_supply_hint` (metadata): Soft target, UI-only, updatable
    ///
    /// **Important**: `None` means unlimited minting is allowed (until `finalize_supply`
    /// is called to lock supply at current `minted` count).
    max_supply: option::Option<u64>,
    minted: u64,
    burned: u64,
    paused: bool,
    /// **Burn Coordination Model**: Controls who can burn NFTs from this collection.
    ///
    /// This field is set at collection creation and is **immutable** - plan your burn model carefully!
    ///
    /// # Two Burn Models
    ///
    /// **Centralized Burn (owner_burn_allowed = false)**:
    /// - Set via `make_burn_cap = true` at creation
    /// - Only the BurnCap holder can burn NFTs via `register_burn_with_cap`
    /// - NFT owners CANNOT self-burn (call to `register_burn_owner` will abort)
    /// - Use cases:
    ///   - Regulatory compliance (controlled destruction)
    ///   - Game mechanics requiring admin approval
    ///   - Deflationary mechanics with governance
    ///   - Collections where burns affect other users
    ///
    /// **Decentralized Burn (owner_burn_allowed = true)**:
    /// - Set via `make_burn_cap = false` at creation
    /// - NFT owners can self-burn via `register_burn_owner`
    /// - No BurnCap is created (permission is decentralized)
    /// - Use cases:
    ///   - Permissionless collections
    ///   - Gaming consumables (potions, tickets)
    ///   - Art projects with owner agency
    ///   - Collections where individual burns don't affect others
    ///
    /// # Important Coordination Notes
    ///
    /// When a BurnCap exists (`owner_burn_allowed = false`):
    /// - External burn functions MUST call `register_burn_with_cap` and require the cap
    /// - Calling `register_burn_owner` will abort with `EOwnerBurnDisabled`
    /// - The BurnCap holder coordinates all burn operations
    ///
    /// When no BurnCap exists (`owner_burn_allowed = true`):
    /// - External burn functions should call `register_burn_owner` directly
    /// - No centralized burn authority exists
    /// - Each NFT owner controls their own burning
    owner_burn_allowed: bool,
}

// ----------------------------
// Unified events (for indexing and aggregation)
// ----------------------------
public struct CapsInitializedEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    metadata_id: object::ID,
    mint_cap_id: object::ID,
    burn_cap_id: option::Option<object::ID>,
    metadata_cap_id: object::ID,
    publisher: address,
}

public struct MintedEvent<phantom T> has copy, drop {
    object: object::ID,
    collection_id: object::ID,
    minter: address,
}

/// Gas-optimized batch mint event for multi-NFT minting operations.
/// Replaces multiple individual MintedEvents with a single aggregated event.
public struct BatchMintedEvent<phantom T> has copy, drop {
    objects: vector<object::ID>,
    collection_id: object::ID,
    minter: address,
    count: u64,
}

public struct BurnedEvent<phantom T> has copy, drop {
    object: object::ID,
    collection_id: object::ID,
    burner: address,
}

public struct MetadataUpdatedEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    metadata_id: object::ID,
    updater: address,
    changed_fields: u8,  // Bitmask indicating which fields changed
    // New values for changed fields (is_some() only if field changed)
    name: option::Option<String>,
    description: option::Option<String>,
    image_url: option::Option<String>,
    external_url: option::Option<option::Option<String>>,
    decimals: option::Option<u8>,
    max_supply_hint: option::Option<option::Option<u64>>,
}

public struct MetadataFrozenEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    metadata_id: object::ID,
    freezer: address,
}

public struct CollectionPausedEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    pauser: address,
}

public struct CollectionResumedEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    resumer: address,
}

// ----------------------------
// Collection initialization (requires Publisher authority)
// ----------------------------
// Note: V2 only provides registry-based collection creation via create_collection_v2()
// and create_unbounded_collection_v2() to ensure global uniqueness per type.


// ----------------------------
// Metadata update (gated by cap)
// ----------------------------
public fun update_metadata<T>(
    _cap: &NftCollectionMetadataCap<T>,
    md: &mut NftCollectionMetadata<T>,
    name: option::Option<String>,
    description: option::Option<String>,
    image_url: option::Option<String>,
    external_url: option::Option<option::Option<String>>,
    decimals: option::Option<u8>,
    max_supply_hint: option::Option<option::Option<u64>>,
    ctx: &TxContext
) {
    // Disallow updates after explicit freeze.
    assert!(!md.metadata_frozen, EMetadataFrozen);

    // Track which fields changed and their new values
    let mut changed_fields: u8 = 0;
    let mut new_name = option::none();
    let mut new_description = option::none();
    let mut new_image_url = option::none();
    let mut new_external_url = option::none();
    let mut new_decimals = option::none();
    let mut new_max_supply_hint = option::none();

    if (name.is_some()) {
        let val = name.destroy_some();
        md.name = val;
        changed_fields = changed_fields | FIELD_NAME;
        new_name = option::some(md.name);
    };

    if (description.is_some()) {
        let val = description.destroy_some();
        md.description = val;
        changed_fields = changed_fields | FIELD_DESCRIPTION;
        new_description = option::some(md.description);
    };

    if (image_url.is_some()) {
        let val = image_url.destroy_some();
        assert!(val.length() > 0, EInvalidImageUrl);
        md.image_url = val;
        changed_fields = changed_fields | FIELD_IMAGE_URL;
        new_image_url = option::some(md.image_url);
    };

    if (external_url.is_some()) {
        let val_opt = external_url.destroy_some();
        if (val_opt.is_some()) {
            let val = val_opt.destroy_some();
            assert!(val.length() > 0, EInvalidExternalUrl);
            md.external_url = option::some(val);
        } else {
            md.external_url = option::none();  // Clear external_url
        };
        changed_fields = changed_fields | FIELD_EXTERNAL_URL;
        new_external_url = option::some(md.external_url);
    };

    if (decimals.is_some()) {
        let val = decimals.destroy_some();
        md.decimals = val;
        changed_fields = changed_fields | FIELD_DECIMALS;
        new_decimals = option::some(md.decimals);
    };

    if (max_supply_hint.is_some()) {
        let val = max_supply_hint.destroy_some();
        md.max_supply_hint = val;
        changed_fields = changed_fields | FIELD_MAX_SUPPLY_HINT;
        new_max_supply_hint = option::some(md.max_supply_hint);
    };

    event::emit(MetadataUpdatedEvent<T>{
        collection_id: md.collection_id,
        metadata_id: object::uid_to_inner(&md.id),
        updater: ctx.sender(),
        changed_fields,
        name: new_name,
        description: new_description,
        image_url: new_image_url,
        external_url: new_external_url,
        decimals: new_decimals,
        max_supply_hint: new_max_supply_hint,
    });
}

// ----------------------------
// Supply tracking (minimal intrusion: called after external mint/burn)
// ----------------------------
/// Record a mint driven by the publisher-held NftMintCap; pass the minted NFT object to add collection_id.
///
/// # Intentional Design: Accepts Any UID with MintCap
///
/// This function **intentionally accepts ANY `&mut UID`** as the `nft` parameter, not just UIDs
/// created by this module. This is a core design decision that enables maximum composability:
///
/// **Why This Openness Matters:**
/// - **External NFT Implementations**: Your NFT struct can live in a separate module with custom logic
/// - **Flexible Architectures**: Add custom fields, abilities, or behaviors to your NFT type
/// - **Standard Integration**: Integrate with existing NFT standards (Sui Kiosk, OriginByte, etc.)
/// - **Separation of Concerns**: The UNFT standard is a *supply tracking layer*, not a full NFT implementation
///
/// **Security Model:**
/// - Caller MUST possess `&NftMintCap<T>` for the type `T` - this is your proof of authority
/// - The cap is type-parameterized, so you can only register mints for collections of that specific type
/// - Collection supply limits (`max_supply`, `paused`) are enforced regardless of where the UID came from
///
/// # Integration Example
///
/// ```move
/// // Your custom NFT in a separate module
/// module game::items {
///     use unft_standard::unft_standard;
///
///     public struct GameNFT has key, store {
///         id: UID,
///         power: u64,
///         rarity: u8,
///         enchantments: vector<String>,
///     }
///
///     // Your custom minting function
///     public fun mint_game_nft(
///         mint_cap: &unft_standard::NftMintCap<GameNFT>,
///         collection: &mut unft_standard::NftCollection<GameNFT>,
///         power: u64,
///         rarity: u8,
///         ctx: &mut TxContext
///     ): GameNFT {
///         // Create your custom NFT object
///         let mut nft_uid = object::new(ctx);
///
///         // Register with UNFT standard for supply tracking
///         unft_standard::register_mint(mint_cap, collection, &mut nft_uid, ctx);
///
///         // Wrap in your custom struct with game-specific fields
///         GameNFT {
///             id: nft_uid,
///             power,
///             rarity,
///             enchantments: vector::empty(),
///         }
///     }
/// }
/// ```
///
/// # Dynamic Field Write Safety
///
/// This function adds a `collection_id` dynamic field to the NFT's UID using `dynamic_field::add`.
/// **IMPORTANT**: This can only be called ONCE per NFT UID. Calling it again on the same UID will
/// abort with `sui::dynamic_field::EFieldAlreadyExists`. This is by design to prevent accidental
/// double-registration and ensure each NFT is associated with exactly one collection.
///
/// ```move
/// // Correct: Register immediately after creating the NFT
/// let nft_uid = object::new(ctx);
/// register_mint(&mint_cap, &mut collection, &mut nft_uid, ctx);
///
/// // WRONG: Calling again aborts
/// // register_mint(&mint_cap, &mut collection, &mut nft_uid, ctx); // ABORTS!
/// ```
///
/// # Parameters
/// - `_mint`: Proof of minting authority (NftMintCap<T>) - must match collection type
/// - `col`: The collection to register the mint against (enforces max_supply and pause state)
/// - `nft`: The newly created NFT's UID (from ANY module - must not have been registered before)
/// - `ctx`: Transaction context for event emission
public fun track_mint<T>(
    _mint: &NftMintCap<T>,
    col: &mut NftCollection<T>,
    nft: &mut UID,
    ctx: &TxContext
) {
    assert_can_mint(col, 1);
    col.minted = col.minted + 1;

    // Add collection_id as a dynamic field to the NFT using typed key
    let collection_id = object::uid_to_inner(&col.id);
    dynamic_field::add<CollectionIdKey, object::ID>(nft, CollectionIdKey(), collection_id);

    event::emit(MintedEvent<T>{
        object: object::uid_to_inner(nft),
        collection_id,
        minter: ctx.sender()
    });
}

/// Record multiple mints in a single call.
///
/// # Dynamic Field Write Safety
/// Each NFT UID in the `nfts` vector must be unique and not previously registered.
/// If any UID already has a `collection_id` field, the entire transaction aborts.
/// See `register_mint` for detailed safety requirements.
///
/// # Gas Optimization
/// Emits a single `BatchMintedEvent` instead of multiple individual `MintedEvent`s,
/// significantly reducing gas costs for batch minting operations.
///
/// # Parameters
/// - `_mint`: Proof of minting authority (NftMintCap)
/// - `col`: The collection to register the mints against
/// - `nfts`: Vector of newly created NFT UIDs (each must be fresh/unregistered)
/// - `ctx`: Transaction context for event emission
public fun track_batch_mint<T>(
    _mint: &NftMintCap<T>,
    col: &mut NftCollection<T>,
    nfts: &mut vector<UID>,
    ctx: &TxContext
) {
    let count = nfts.length();
    if (count == 0) {
        return
    };
    assert_can_mint(col, count);
    col.minted = col.minted + count;

    let collection_id = object::uid_to_inner(&col.id);
    let mut object_ids = vector::empty<object::ID>();
    let mut i = 0;

    while (i < count) {
        let nft_ref = &mut nfts[i];
        dynamic_field::add<CollectionIdKey, object::ID>(nft_ref, CollectionIdKey(), collection_id);
        let nft_id = object::uid_to_inner(nft_ref);
        object_ids.push_back(nft_id);
        i = i + 1;
    };

    // Gas optimization: emit single batch event instead of N individual events
    event::emit(BatchMintedEvent<T>{
        objects: object_ids,
        collection_id,
        minter: ctx.sender(),
        count,
    });
}

/// Burn with burn capability (restricted).
///
/// ⚠️ **SECURITY WARNING: Ownership Verification Required**
///
/// This function accepts ANY UID and destroys it. **The caller MUST ensure ownership verification
/// before calling this function.** The UNFT standard is a supply tracking layer, not a complete
/// NFT implementation, and intentionally accepts any UID to maximize composability.
///
/// # Caller Responsibilities
///
/// External modules MUST ensure:
/// 1. The UID comes from an object owned by the transaction sender
/// 2. The NFT struct has been properly unpacked (proving ownership)
/// 3. No unsafe ID-to-UID conversions are used
///
/// # Design Rationale
///
/// Accepting any UID allows:
/// - Integration with any NFT implementation (Sui Kiosk, OriginByte, etc.)
/// - Custom NFT struct fields and behaviors
/// - Flexible architectural patterns
/// - Maximum composability across the ecosystem
///
/// # ✅ Correct Usage Pattern
///
/// ```move
/// module my_nft::safe {
///     public fun burn_nft(
///         nft: MyNFT,  // Takes owned object - proves ownership
///         burn_cap: &NftBurnCap<MyNFT>,
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // Unpack owned object - only possible if caller owns it
///         let MyNFT { id: uid, custom_field, ... } = nft;
///
///         // Now safe to register burn
///         unft::register_burn_with_cap(burn_cap, collection, uid, ctx);
///     }
/// }
/// ```
///
/// # ❌ Unsafe Pattern - DO NOT DO THIS
///
/// ```move
/// module bad_nft::unsafe {
///     public fun unsafe_burn(
///         nft_id: ID,  // ❌ Only accepts ID, no ownership proof
///         burn_cap: &NftBurnCap<MyNFT>,
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // ❌ There's no way to get UID from ID in safe Move
///         // ❌ If there was, it would allow burning anyone's NFT
///         // Move's type system prevents this, but don't try to bypass it
///     }
/// }
/// ```
///
/// # Kiosk Integration Example
///
/// When burning NFTs from a Kiosk, you MUST use KioskOwnerCap to prove ownership:
///
/// ```move
/// module my_nft::kiosk_integration {
///     use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
///
///     public fun burn_from_kiosk(
///         kiosk: &mut Kiosk,
///         kiosk_cap: &KioskOwnerCap,  // ✅ Proves Kiosk ownership
///         nft_id: ID,
///         burn_cap: &NftBurnCap<MyNFT>,
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // Kiosk validates ownership via KioskOwnerCap
///         let nft = kiosk::take<MyNFT>(kiosk, kiosk_cap, nft_id);
///
///         // Now we own the NFT, safe to unpack and burn
///         let MyNFT { id: uid, ... } = nft;
///         unft::register_burn_with_cap(burn_cap, collection, uid, ctx);
///     }
/// }
/// ```
///
/// # Transfer Policy Integration
///
/// If your NFT type has a TransferPolicy, ensure proper policy resolution:
///
/// ```move
/// public fun burn_with_policy(
///     nft: MyNFT,
///     burn_cap: &NftBurnCap<MyNFT>,
///     collection: &mut NftCollection<MyNFT>,
///     policy: &TransferPolicy<MyNFT>,  // May be required for policy rules
///     ctx: &TxContext
/// ) {
///     // Check if burning requires policy approval
///     // (implementation depends on your policy rules)
///
///     let MyNFT { id: uid, ... } = nft;
///     unft::register_burn_with_cap(burn_cap, collection, uid, ctx);
/// }
/// ```
///
/// # Security Guarantees
///
/// - The BurnCap proves authority to burn NFTs of type T
/// - The collection_id verification (line 455) ensures the NFT belongs to this collection
/// - Type parameter T ensures only NFTs of the correct type can be burned
/// - The UID is deleted, preventing double-burn
///
/// # What This Function Does NOT Verify
///
/// - NFT ownership (caller's responsibility)
/// - Transfer policy compliance (caller's responsibility if applicable)
/// - Custom burn conditions (caller's responsibility)
///
/// External modules implement these checks based on their specific requirements.
public fun track_burn<T>(
    _cap: &NftBurnCap<T>,
    col: &mut NftCollection<T>,
    mut nft_uid: UID,
    ctx: &TxContext
) {
    col.burned = col.burned + 1;

    let collection_id = object::uid_to_inner(&col.id);
    let burned_id = object::uid_to_inner(&nft_uid);

    // Remove the typed dynamic field before deleting the object
    let removed = dynamic_field::remove<CollectionIdKey, object::ID>(&mut nft_uid, CollectionIdKey());
    assert!(removed == collection_id, EMetadataCollectionMismatch);
    nft_uid.delete();

    event::emit(BurnedEvent<T>{
        object: burned_id,
        collection_id,
        burner: ctx.sender()
    });
}

/// Burn by owner (when no BurnCap configured).
///
/// ⚠️ **SECURITY WARNING: Ownership Verification Required**
///
/// This function accepts ANY UID and destroys it. **The caller MUST ensure ownership verification
/// before calling this function.** This function is only available when the collection was created
/// with `owner_burn_allowed = true` (i.e., `make_burn_cap = false` at creation).
///
/// # Burn Model Enforcement
///
/// This function will abort with `EOwnerBurnDisabled` if the collection has a BurnCap
/// (created with `make_burn_cap = true`). See the collection's `owner_burn_allowed` field
/// and the detailed documentation at lines 111-148 for the two burn coordination models.
///
/// # Caller Responsibilities
///
/// External modules MUST ensure:
/// 1. The UID comes from an object owned by the transaction sender
/// 2. The NFT struct has been properly unpacked (proving ownership)
/// 3. No unsafe ID-to-UID conversions are used
///
/// # Design Rationale
///
/// This decentralized burn model allows NFT owners to burn their own NFTs without requiring
/// a centralized authority. Use cases include:
/// - Permissionless collections
/// - Gaming consumables (potions, tickets)
/// - Art projects with owner agency
/// - Collections where individual burns don't affect others
///
/// # ✅ Correct Usage Pattern
///
/// ```move
/// module my_nft::owner_burn {
///     public fun burn_my_nft(
///         nft: MyNFT,  // Takes owned object - proves ownership
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // Unpack owned object - only possible if caller owns it
///         let MyNFT { id: uid, ... } = nft;
///
///         // Register owner burn (no cap required)
///         unft::register_burn_owner(collection, uid, ctx);
///     }
/// }
/// ```
///
/// # ❌ Unsafe Pattern - DO NOT DO THIS
///
/// ```move
/// module bad_nft::unsafe_owner_burn {
///     public fun unsafe_burn(
///         nft_id: ID,  // ❌ Only accepts ID, no ownership proof
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // ❌ There's no way to get UID from ID in safe Move
///         // ❌ This would allow burning anyone's NFT
///     }
/// }
/// ```
///
/// # Kiosk Integration Example
///
/// ```move
/// module my_nft::kiosk_owner_burn {
///     use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
///
///     public fun burn_from_my_kiosk(
///         kiosk: &mut Kiosk,
///         kiosk_cap: &KioskOwnerCap,  // ✅ Proves Kiosk ownership
///         nft_id: ID,
///         collection: &mut NftCollection<MyNFT>,
///         ctx: &TxContext
///     ) {
///         // Kiosk validates ownership
///         let nft = kiosk::take<MyNFT>(kiosk, kiosk_cap, nft_id);
///
///         let MyNFT { id: uid, ... } = nft;
///         unft::register_burn_owner(collection, uid, ctx);
///     }
/// }
/// ```
///
/// # Security Guarantees
///
/// - Collection's `owner_burn_allowed` flag enforces burn model consistency
/// - The collection_id verification ensures the NFT belongs to this collection
/// - Type parameter T ensures only NFTs of the correct type can be burned
/// - The UID is deleted, preventing double-burn
///
/// # What This Function Does NOT Verify
///
/// - NFT ownership (caller's responsibility)
/// - Transfer policy compliance (caller's responsibility if applicable)
/// - Custom burn conditions (caller's responsibility)
///
/// See `track_burn` for the alternative centralized burn model.
public fun track_burn_by_owner<T>(
    col: &mut NftCollection<T>,
    mut nft_uid: UID,
    ctx: &TxContext
) {
    assert!(col.owner_burn_allowed, EOwnerBurnDisabled);
    col.burned = col.burned + 1;

    let collection_id = object::uid_to_inner(&col.id);
    let burned_id = object::uid_to_inner(&nft_uid);

    // Remove the typed dynamic field before deleting the object
    let removed = dynamic_field::remove<CollectionIdKey, object::ID>(&mut nft_uid, CollectionIdKey());
    assert!(removed == collection_id, EMetadataCollectionMismatch);
    nft_uid.delete();

    event::emit(BurnedEvent<T>{
        object: burned_id,
        collection_id,
        burner: ctx.sender()
    });
}

/// Pause minting-related operations for the collection.
///
/// # Pause Semantics (Registration-Level)
///
/// **What gets paused:**
/// - `register_mint` and `register_batch_mint` calls are blocked
/// - Supply tracking for this collection stops incrementing
///
/// **What is NOT affected:**
/// - External modules can still create NFT objects (if they implement their own minting logic)
/// - Existing NFTs remain unaffected and fully functional
/// - Burn operations continue to work normally
///
/// **Design Rationale:**
/// The UNFT standard is an opt-in supply tracking layer for external NFT implementations.
/// Pausing prevents registration with the standard, but cannot control external NFT creation
/// logic which lives in separate modules. This separation allows:
/// - Collection owners to halt supply increases without modifying external code
/// - Emergency stops for supply tracking issues
/// - Phased launches coordinated with off-chain systems
///
/// **Important:** Collection must have been created with `pausable = true`, otherwise
/// this function will abort with `ECollectionNotPausable`.
public fun pause_collection<T>(
    _cap: &NftCollectionMetadataCap<T>,
    metadata: &NftCollectionMetadata<T>,
    col: &mut NftCollection<T>,
    ctx: &TxContext
) {
    // Defensive check: ensure metadata and collection are properly linked
    assert!(col.metadata_id == object::uid_to_inner(&metadata.id), EMetadataCollectionMismatch);
    assert!(metadata.pausable, ECollectionNotPausable);

    // Gas optimization: skip if already paused (avoid redundant state write & event)
    if (col.paused) {
        return
    };

    col.paused = true;

    event::emit(CollectionPausedEvent<T>{
        collection_id: object::uid_to_inner(&col.id),
        pauser: ctx.sender(),
    });
}

/// Resume minting-related operations for the collection.
///
/// Re-enables `register_mint` and `register_batch_mint` after a pause.
/// See `pause_collection` for detailed semantics.
public fun resume_collection<T>(
    _cap: &NftCollectionMetadataCap<T>,
    metadata: &NftCollectionMetadata<T>,
    col: &mut NftCollection<T>,
    ctx: &TxContext
) {
    // Defensive check: ensure metadata and collection are properly linked
    assert!(col.metadata_id == object::uid_to_inner(&metadata.id), EMetadataCollectionMismatch);
    assert!(metadata.pausable, ECollectionNotPausable);

    // Gas optimization: skip if already resumed (avoid redundant state write & event)
    if (!col.paused) {
        return
    };

    col.paused = false;

    event::emit(CollectionResumedEvent<T>{
        collection_id: object::uid_to_inner(&col.id),
        resumer: ctx.sender(),
    });
}

// ----------------------------
// Convenience accessors
// ----------------------------

// Composite supply getter
public fun supply<T>(col: &NftCollection<T>): (u64, u64, option::Option<u64>) {
    (col.minted, col.burned, col.max_supply)
}

// Individual supply fields
/// Returns the enforced maximum supply cap for the collection.
///
/// - `Some(cap)`: Collection has a hard limit enforced on-chain
/// - `None`: Unlimited supply until `finalize_supply` is called
///
/// **Note**: Renamed from `get_max_supply` for Move 2024 compliance.
/// Getter functions should be named after the field without `get_` prefix.
public fun max_supply<T>(col: &NftCollection<T>): option::Option<u64> {
    col.max_supply
}

/// Returns the total number of NFTs minted for this collection.
/// This count increases with each `register_mint` or `register_batch_mint` call.
///
/// **Note**: Renamed from `get_minted` for Move 2024 compliance.
public fun minted<T>(col: &NftCollection<T>): u64 {
    col.minted
}

/// Returns the total number of NFTs burned from this collection.
/// This count increases with each `register_burn_with_cap` or `register_burn_owner` call.
///
/// **Note**: Renamed from `get_burned` for Move 2024 compliance.
public fun burned<T>(col: &NftCollection<T>): u64 {
    col.burned
}

// Collection state
/// Returns whether the collection is currently paused.
/// When paused, all minting operations are disabled.
public fun is_paused<T>(col: &NftCollection<T>): bool {
    col.paused
}

/// Returns whether NFT owners can burn their own NFTs without requiring a BurnCap.
///
/// - `true`: Owners can burn via `track_burn_by_owner` (no BurnCap created at init)
/// - `false`: Only BurnCap holder can burn via `track_burn`
public fun allows_owner_burn<T>(col: &NftCollection<T>): bool {
    col.owner_burn_allowed
}

// References
/// Returns the ID of the associated NftCollectionMetadata object.
/// Use this to fetch metadata via `sui::object::id_to_address` or similar.
///
/// **Note**: Renamed from `get_metadata_id` for Move 2024 compliance.
public fun metadata_id<T>(col: &NftCollection<T>): object::ID {
    col.metadata_id
}

/// Check if minting is allowed for the specified amount.
///
/// Returns `false` if:
/// - `amount` is 0
/// - Collection is paused
/// - Minting would exceed `max_supply` (if set)
///
/// Returns `true` otherwise.
///
/// # Use Case
///
/// External modules can use this to pre-check mint eligibility before attempting
/// to mint, providing better user experience by failing early with custom error
/// messages instead of relying on `register_mint` assertions.
///
/// # Example
///
/// ```move
/// module my_nft::mint {
///     const ECannotMint: u64 = 1;
///     const EMintLimitReached: u64 = 2;
///
///     public fun safe_mint(
///         mint_cap: &NftMintCap<MyNFT>,
///         collection: &mut NftCollection<MyNFT>,
///         amount: u64,
///         ctx: &mut TxContext
///     ) {
///         // Pre-check with custom error
///         assert!(unft::can_mint(collection, amount), ECannotMint);
///
///         // Check remaining supply for better error message
///         if let Some(remaining) = unft::remaining_mintable(collection) {
///             assert!(amount <= remaining, EMintLimitReached);
///         };
///
///         // Proceed with mint...
///     }
/// }
/// ```
///
/// **Reference**: Better Error Handling - Rule 3: Return bool Instead of assert
public fun can_mint<T>(col: &NftCollection<T>, amount: u64): bool {
    if (amount == 0) return false;
    if (col.paused) return false;
    if (col.max_supply.is_some()) {
        let max_supply_ref = col.max_supply.borrow();
        return col.minted + amount <= *max_supply_ref
    };
    true
}

/// Get remaining mintable quantity for the collection.
///
/// Returns:
/// - `None` if the collection has unlimited supply (no `max_supply` set)
/// - `Some(0)` if the collection has reached its maximum supply
/// - `Some(n)` where n > 0 for the remaining mintable quantity
///
/// # Use Case
///
/// External modules can use this to display remaining supply to users or to
/// implement custom minting limits.
///
/// # Example
///
/// ```move
/// module my_nft::mint_info {
///     const EMintLimitReached: u64 = 1;
///     const EExceedsRemainingSupply: u64 = 2;
///
///     public fun mint_with_limit(
///         mint_cap: &NftMintCap<MyNFT>,
///         collection: &mut NftCollection<MyNFT>,
///         amount: u64,
///         ctx: &mut TxContext
///     ) {
///         // Check if collection has a supply limit
///         if let Some(remaining) = unft::remaining_mintable(collection) {
///             assert!(remaining > 0, EMintLimitReached);
///             assert!(amount <= remaining, EExceedsRemainingSupply);
///         };
///
///         // Proceed with mint...
///     }
///
///     /// Display function for UI
///     public fun get_mint_status(col: &NftCollection<MyNFT>): (u64, option::Option<u64>) {
///         let minted = unft::minted(col);
///         let remaining = unft::remaining_mintable(col);
///         (minted, remaining)
///     }
/// }
/// ```
///
/// **Reference**: Better Error Handling - Rule 1: Handle All Possible Scenarios
public fun remaining_supply<T>(col: &NftCollection<T>): option::Option<u64> {
    if (col.max_supply.is_none()) {
        return option::none()
    };
    let max = *col.max_supply.borrow();
    if (col.minted >= max) {
        option::some(0)
    } else {
        option::some(max - col.minted)
    }
}

/// Internal helper to validate minting is allowed.
/// Enforces `max_supply` limit if set (aborts if exceeded).
/// Called by both `register_mint` and `register_batch_mint`.
fun assert_can_mint<T>(col: &NftCollection<T>, amount: u64) {
    assert!(amount > 0, EInvalidMintAmount);
    assert!(!col.paused, ECollectionPaused);
    if (col.max_supply.is_some()) {
        let max_supply_ref = col.max_supply.borrow();
        assert!(col.minted + amount <= *max_supply_ref, EMaxSupplyExceeded);
    };
}

// ----------------------------
// Helper functions
// ----------------------------
fun validate_urls(image_url: &String, external_url: &option::Option<String>) {
    // Basic URL validation - checking if non-empty
    assert!(image_url.length() > 0, EInvalidImageUrl);
    if (external_url.is_some()) {
        let url_ref = external_url.borrow();
        assert!(url_ref.length() > 0, EInvalidExternalUrl);
    };
}

/// Internal helper to create collection components
fun new_collection_components<T>(
    name: String,
    description: String,
    image_url: String,
    external_url: option::Option<String>,
    decimals: u8,
    max_supply: option::Option<u64>,
    supply_hint: option::Option<u64>,
    pausable: bool,
    make_burn_cap: bool,
    ctx: &mut TxContext
) : (
    NftCollectionMetadata<T>,
    NftCollection<T>,
    NftMintCap<T>,
    option::Option<NftBurnCap<T>>,
    NftCollectionMetadataCap<T>
) {
    validate_urls(&image_url, &external_url);

    // Create UIDs first to get IDs for cross-referencing
    let md_uid = object::new(ctx);
    let col_uid = object::new(ctx);

    // Extract IDs
    let metadata_id = object::uid_to_inner(&md_uid);
    let collection_id = object::uid_to_inner(&col_uid);

    // Create metadata with collection_id reference
    let md = NftCollectionMetadata<T>{
        id: md_uid,
        collection_id,
        version: 1u8,
        name,
        description,
        image_url,
        external_url,
        decimals,
        max_supply_hint: supply_hint,
        pausable,
        metadata_frozen: false,
        reserved: vector[],
    };

    // Create collection with metadata_id reference
    let col = NftCollection<T>{
        id: col_uid,
        metadata_id,
        max_supply,
        minted: 0,
        burned: 0,
        paused: false,
        owner_burn_allowed: !make_burn_cap,
    };

    let mint = NftMintCap<T>{ id: object::new(ctx) };
    let burn_opt = if (make_burn_cap) {
        option::some(NftBurnCap<T>{ id: object::new(ctx) })
    } else {
        option::none<NftBurnCap<T>>()
    };
    let meta = NftCollectionMetadataCap<T>{ id: object::new(ctx) };

    (md, col, mint, burn_opt, meta)
}

#[test_only]
public(package) fun metadata_refs<T>(
    md: &NftCollectionMetadata<T>
): (&object::ID, &u8, &String, &String, &String, &option::Option<String>, &u8, &option::Option<u64>, &bool, &bool) {
    (
        &md.collection_id,
        &md.version,
        &md.name,
        &md.description,
        &md.image_url,
        &md.external_url,
        &md.decimals,
        &md.max_supply_hint,
        &md.pausable,
        &md.metadata_frozen
    )
}

public(package) fun collection_snapshot<T>(
    col: &NftCollection<T>
): (&object::ID, &option::Option<u64>, u64, u64, bool) {
    (&col.metadata_id, &col.max_supply, col.minted, col.burned, col.paused)
}

#[test_only]
public(package) fun destroy_components_for_tests<T>(
    metadata: NftCollectionMetadata<T>,
    collection: NftCollection<T>,
    mint: NftMintCap<T>,
    burn_opt: option::Option<NftBurnCap<T>>,
    meta_cap: NftCollectionMetadataCap<T>
) {
    let NftCollectionMetadata { id, .. } = metadata;
    id.delete();

    let NftCollection { id, metadata_id: _, .. } = collection;
    id.delete();

    let NftMintCap { id } = mint;
    id.delete();

    if (burn_opt.is_some()) {
        let burn = burn_opt.destroy_some();
        let NftBurnCap { id } = burn;
        id.delete();
    } else {
        burn_opt.destroy_none();
    };

    let NftCollectionMetadataCap { id } = meta_cap;
    id.delete();
}

// ----------------------------
// Testing helpers
// ----------------------------
// Note: V2 tests should use new_collection_components() directly or create_collection_v2()
// to ensure proper registry integration.

// ============================
// Global Registry (optional, v2 API)
// ============================

public struct NftRegistry has key {
    id: UID,
}

/// Stored under the registry's dynamic field keyed by `TypeName`.
public struct CollectionLocator has store, copy, drop {
    collection_id: object::ID,
    metadata_id: object::ID,
}

// Locator getters
public fun locator_collection_id(loc: CollectionLocator): object::ID { loc.collection_id }
public fun locator_metadata_id(loc: CollectionLocator): object::ID { loc.metadata_id }

public struct RegistryInitializedEvent has copy, drop {
    registry_id: object::ID,
}

public struct CollectionRegisteredEvent<phantom T> has copy, drop {
    registry_id: object::ID,
    collection_id: object::ID,
    metadata_id: object::ID,
    creator: address,
}

public struct SupplyFinalizedEvent<phantom T> has copy, drop {
    collection_id: object::ID,
    cap: u64,
    finalizer: address,
}

/// Called once on package publish.
fun init(ctx: &mut TxContext) {
    let reg = NftRegistry { id: object::new(ctx) };
    let registry_id = object::uid_to_inner(&reg.id);
    transfer::share_object(reg);
    event::emit(RegistryInitializedEvent { registry_id });
}

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx)
}

/// Returns true if a collection for type T is already registered.
public fun collection_exists<T>(reg: &NftRegistry): bool {
    dynamic_field::exists_(&reg.id, type_name::with_defining_ids<T>())
}

/// Get locator for type T from the registry (returns copy).
public fun get_locator<T>(reg: &NftRegistry): CollectionLocator {
    assert!(collection_exists<T>(reg), ENotRegistered);
    *dynamic_field::borrow(&reg.id, type_name::with_defining_ids<T>())
}

/// Create a collection with registry uniqueness enforcement.
public fun create_collection_v2<T>(
    publisher: &Publisher,
    registry: &mut NftRegistry,
    name: String,
    description: String,
    image_url: String,
    external_url: option::Option<String>,
    decimals: u8,
    max_supply: option::Option<u64>,
    pausable: bool,
    make_burn_cap: bool,
    ctx: &mut TxContext
) : (
    NftMintCap<T>,
    option::Option<NftBurnCap<T>>,
    NftCollectionMetadataCap<T>
) {
    assert!(publisher.from_package<T>(), ENotAuthorizedPublisher);
    assert!(!collection_exists<T>(registry), EAlreadyRegistered);

    let (md, col, mint, burn_opt, meta_cap) =
        new_collection_components<T>(
            name, description, image_url, external_url, decimals,
            max_supply, max_supply, pausable, make_burn_cap, ctx
        );

    let collection_id = object::uid_to_inner(&col.id);
    let metadata_id = object::uid_to_inner(&md.id);
    let registry_id = object::uid_to_inner(&registry.id);
    let mint_cap_id = object::uid_to_inner(&mint.id);
    let burn_cap_id = if (burn_opt.is_some()) {
        option::some(object::uid_to_inner(&burn_opt.borrow().id))
    } else {
        option::none<object::ID>()
    };
    let metadata_cap_id = object::uid_to_inner(&meta_cap.id);

    // Share objects before writing their IDs into registry.
    transfer::share_object(md);
    transfer::share_object(col);

    // Register locator under TypeName(T) -> CollectionLocator
    dynamic_field::add(
        &mut registry.id,
        type_name::with_defining_ids<T>(),
        CollectionLocator { collection_id, metadata_id }
    );

    // Emit capability initialization event
    event::emit(CapsInitializedEvent<T>{
        collection_id,
        metadata_id,
        mint_cap_id,
        burn_cap_id,
        metadata_cap_id,
        publisher: ctx.sender(),
    });

    event::emit(CollectionRegisteredEvent<T>{
        registry_id,
        collection_id,
        metadata_id,
        creator: ctx.sender(),
    });

    (mint, burn_opt, meta_cap)
}

/// Unlimited supply variant of v2.
public fun create_unlimited_collection_v2<T>(
    publisher: &Publisher,
    registry: &mut NftRegistry,
    name: String,
    description: String,
    image_url: String,
    external_url: option::Option<String>,
    decimals: u8,
    pausable: bool,
    make_burn_cap: bool,
    ctx: &mut TxContext
) : (
    NftMintCap<T>,
    option::Option<NftBurnCap<T>>,
    NftCollectionMetadataCap<T>
) {
    create_collection_v2<T>(
        publisher,
        registry,
        name,
        description,
        image_url,
        external_url,
        decimals,
        option::none<u64>(),
        pausable,
        make_burn_cap,
        ctx
    )
}

/// Permanently freeze metadata by consuming the MetadataCap.
public fun freeze_metadata<T>(
    cap: NftCollectionMetadataCap<T>,
    md: &mut NftCollectionMetadata<T>,
    ctx: &TxContext
) {
    md.metadata_frozen = true;
    let NftCollectionMetadataCap { id } = cap;
    id.delete();
    event::emit(MetadataFrozenEvent<T>{
        collection_id: md.collection_id,
        metadata_id: object::uid_to_inner(&md.id),
        freezer: ctx.sender(),
    });
}

/// Make supply fixed at the current minted amount and burn the MintCap.
///
/// This is a one-way operation that:
/// 1. Sets `max_supply = Some(current_minted_count)` if not already set
/// 2. Burns the MintCap so no more minting is possible
/// 3. Provides on-chain proof of final supply
///
/// **Use Cases**:
/// - Convert unlimited collection to fixed supply
/// - Lock supply based on market demand
/// - Create provable scarcity after initial sale
///
/// **Important**:
/// - Aborts with `EAlreadyFixedSupply` if `max_supply` was already set at
///   collection creation. This prevents accidentally lowering a pre-defined cap.
/// - Aborts with `ECannotFinalizeZeroSupply` if no NFTs have been minted yet.
///   You must mint at least one NFT before finalizing supply.
public fun finalize_supply<T>(
    mint: NftMintCap<T>,
    col: &mut NftCollection<T>,
    ctx: &TxContext
) {
    // If max_supply already set, do not override.
    assert!(col.max_supply.is_none(), EAlreadyFixedSupply);
    // Prevent finalizing at zero supply (likely a mistake)
    assert!(col.minted > 0, ECannotFinalizeZeroSupply);
    col.max_supply = option::some(col.minted);
    let NftMintCap { id } = mint;
    id.delete();
    event::emit(SupplyFinalizedEvent<T>{
        collection_id: object::uid_to_inner(&col.id),
        cap: col.minted,
        finalizer: ctx.sender(),
    });
}

// ----------------------------
// Testing helpers
// ----------------------------
/// Create a test collection for use in tests (without registry)
/// This mirrors V1 API for test compatibility
#[test_only]
public fun create_test_collection<T>(
    ctx: &mut TxContext
): NftCollection<T> {
    let (md, col, mint, burn_opt, meta_cap) = new_collection_components<T>(
        b"Test Collection".to_string(),
        b"A test NFT collection".to_string(),
        b"https://example.com/image.png".to_string(),
        option::none(),
        0,
        option::none(),
        option::none(),
        false,
        false,
        ctx
    );

    // Clean up metadata and caps
    let NftCollectionMetadata { id, .. } = md;
    id.delete();

    let NftMintCap { id } = mint;
    id.delete();

    if (burn_opt.is_some()) {
        let burn = burn_opt.destroy_some();
        let NftBurnCap { id } = burn;
        id.delete();
    } else {
        burn_opt.destroy_none();
    };

    let NftCollectionMetadataCap { id } = meta_cap;
    id.delete();

    col
}

// ----------- Convenience getters (public visibility) -----------
public fun name<T>(md: &NftCollectionMetadata<T>): &String { &md.name }
public fun description<T>(md: &NftCollectionMetadata<T>): &String { &md.description }
public fun image_url<T>(md: &NftCollectionMetadata<T>): &String { &md.image_url }
public fun external_url<T>(md: &NftCollectionMetadata<T>): &option::Option<String> { &md.external_url }
public fun decimals<T>(md: &NftCollectionMetadata<T>): u8 { md.decimals }
public fun metadata_frozen<T>(md: &NftCollectionMetadata<T>): bool { md.metadata_frozen }
public fun version<T>(md: &NftCollectionMetadata<T>): u8 { md.version }

// ----------- UNFT Discoverability Helpers (Phase 6.0 & 6.1) -----------

#[error]
const ECollectionIdNotFound: vector<u8> =
    b"NFT does not have a collection_id dynamic field";

/// Helper to retrieve collection_id from an NFT (strict version - aborts if not found).
/// Avoids need for external code to know about CollectionIdKey.
///
/// **Note**: Renamed from `get_nft_collection_id` for Move 2024 compliance.
public fun nft_collection_id(nft: &UID): object::ID {
    assert!(
        dynamic_field::exists_<CollectionIdKey>(nft, CollectionIdKey()),
        ECollectionIdNotFound
    );
    *dynamic_field::borrow<CollectionIdKey, object::ID>(nft, CollectionIdKey())
}

/// Try-get variant: returns Option instead of aborting when missing.
///
/// **Note**: Renamed from `try_get_nft_collection_id` for Move 2024 compliance.
public fun try_nft_collection_id(nft: &UID): option::Option<object::ID> {
    if (dynamic_field::exists_<CollectionIdKey>(nft, CollectionIdKey())) {
        option::some(*dynamic_field::borrow<CollectionIdKey, object::ID>(nft, CollectionIdKey()))
    } else {
        option::none()
    }
}

/// Convenience: get or fallback default (useful in indexers/tests).
///
/// **Note**: Renamed from `get_nft_collection_id_or_default` for Move 2024 compliance.
public fun nft_collection_id_or(
    nft: &UID,
    default: object::ID,
): object::ID {
    let opt = try_nft_collection_id(nft);
    if (opt.is_some()) {
        opt.destroy_some()
    } else {
        default
    }
}

/// Check if NFT has collection_id (for validation)
public fun has_collection_id(nft: &UID): bool {
    dynamic_field::exists_<CollectionIdKey>(nft, CollectionIdKey())
}

/// Batch get collection IDs.
///
/// **Note**: Renamed from `batch_get_collection_ids` for Move 2024 compliance.
public fun nft_collection_ids(nfts: &vector<UID>): vector<object::ID> {
    let mut collection_ids = vector[];
    let len = nfts.length();
    let mut i = 0;

    while (i < len) {
        let nft = &nfts[i];
        let collection_id = nft_collection_id(nft);
        collection_ids.push_back(collection_id);
        i = i + 1;
    };

    collection_ids
}
