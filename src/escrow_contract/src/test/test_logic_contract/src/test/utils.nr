use crate::TestLogic;
use aztec::{
    event::{event_interface::EventInterface, EventSelector},
    protocol::{
        address::AztecAddress,
        point::Point,
        public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM},
        traits::Serialize,
    },
    test::helpers::test_environment::TestEnvironment,
};
use escrow_contract::types::escrow_details_event::EscrowDetailsLogContent;

// --- TXE private events (`txe_oracles::get_private_events` is crate-private; we duplicate its oracle only) ---
//
// CANONICAL VALUES: keep in lockstep with aztec-nr when bumping the `aztec` dependency (this crate's Nargo.toml tag).
// Source: https://github.com/AztecProtocol/aztec-packages/blob/v4.2.0-aztecnr-rc.2/noir-projects/aztec-nr/aztec/src/test/helpers/txe_oracles.nr#L13-L14
// (`MAX_PRIVATE_EVENTS_PER_TXE_QUERY` and `MAX_EVENT_SERIALIZATION_LENGTH` are module-private there, so not importable.)
global MAX_PRIVATE_EVENTS_PER_TXE_QUERY: u32 = 5;
global MAX_EVENT_SERIALIZATION_LENGTH: u32 = 10;

#[oracle(aztec_txe_getPrivateEvents)]
unconstrained fn get_private_events_oracle(
    selector: EventSelector,
    contract_address: AztecAddress,
    scope: AztecAddress,
    ) -> ([[Field; MAX_EVENT_SERIALIZATION_LENGTH]; MAX_PRIVATE_EVENTS_PER_TXE_QUERY], [u32; MAX_PRIVATE_EVENTS_PER_TXE_QUERY], u32) {}

pub unconstrained fn deploy_logic(
    env: &mut TestEnvironment,
    escrow_class_id: Field,
) -> AztecAddress {
    let owner = env.create_light_account();

    // Deploy logic contract
    let initializer_call_interface = TestLogic::interface().constructor(escrow_class_id);
    let logic_contract = env.deploy("@test_logic_contract/TestLogic").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    logic_contract
}

pub unconstrained fn get_test_vector() -> (PublicKeys, Field, PublicKeys, Field) {
    // Secret key 1: derived using 1 as the seed
    let secret_key_1: Field = 1;

    let npk_x_1: Field = 0x17227b1fff943cb7386368b044855225acea756c7f4bfcc098630fb88de55a35;
    let npk_y_1: Field = 0x14a50cb11d05246965399813fc209b92632cf205c1333bafa343c41e4b29d0b8;
    let ivpk_x_1: Field = 0x1135429dcf9877365a488bd5417bcd2e042b6b79344be675577524610e402dc7;
    let ivpk_y_1: Field = 0x1184a707e50a7b7932b6d15c8daaaf8eda89e62fa44142f78c40c978cefaa5c3;
    let ovpk_x_1: Field = 0x109ff6b46a6f6e236f4f4a19b56ad60c6a5a9684be76edc2d94c4ec856f23b1a;
    let ovpk_y_1: Field = 0x2bf93b572014c0501320f338b72ad5286cdaea06062814e6f12cf3e63b67c0ce;
    let tpk_x_1: Field = 0x0c4ffde4cefc58fa18045ee1249d0d2fc9f65a2308f408c6a5f1feff56778c1a;
    let tpk_y_1: Field = 0x1ef6fce001c800647bb2b7137517181306c713f671c0e65339dd11d57c863ee8;

    let public_keys_1 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_1, y: npk_y_1, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_1, y: ivpk_y_1, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_1, y: ovpk_y_1, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_1, y: tpk_y_1, is_infinite: false } },
    };

    // Secret key 2: string "RANDOM_SECRET_KEY" left-padded to 32 bytes with spaces
    // 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559
    let secret_key_2: Field = 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559;

    let npk_x_2: Field = 0x26344cea910770d5e95b7f80c9abddcae5fb34725e880260dc43cdf6a74b5f2f;
    let npk_y_2: Field = 0x1e884cb9a43dd3f40fe4e9d631baad1be5a56392b0ef96b797ca769c14da2578;
    let ivpk_x_2: Field = 0x0fa1458fa21d36ebeaeed4a886b7ead77acce59c743bca9d9205de972593e600;
    let ivpk_y_2: Field = 0x1630b61e635d63c2aaa28afda105410a6f3ca23dc0132e5d0314f93d13c54d09;
    let ovpk_x_2: Field = 0x14757672572bc282a967dda767d0ede9430700f4a9e024e2f9914bbfd9a48651;
    let ovpk_y_2: Field = 0x270a30dbd666fe78c5e54cf5bbc03d6f81a288a24f110b6b72998faca4705294;
    let tpk_x_2: Field = 0x05c9d2066d7aedbad14137c0b34827eda0b300f3808aa221b519a9959facec88;
    let tpk_y_2: Field = 0x0cc1c1631501a99ed1797f4d701df03c9663989fee1fb311266459b47f523e07;

    let public_keys_2 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_2, y: npk_y_2, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_2, y: ivpk_y_2, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_2, y: ovpk_y_2, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_2, y: tpk_y_2, is_infinite: false } },
    };

    (public_keys_1, secret_key_1, public_keys_2, secret_key_2)
}

/// Private events emitted in the last mined transaction, visible to `scope` (the recipient), from `contract_address`.
pub unconstrained fn get_private_events_from_last_tx(
    selector: EventSelector,
    contract_address: AztecAddress,
    scope: AztecAddress,
    ) -> BoundedVec<BoundedVec<Field, MAX_EVENT_SERIALIZATION_LENGTH>, MAX_PRIVATE_EVENTS_PER_TXE_QUERY> {
    std::static_assert(
        <EscrowDetailsLogContent as Serialize>::N <= MAX_EVENT_SERIALIZATION_LENGTH,
        "EscrowDetailsLogContent::N exceeds MAX_EVENT_SERIALIZATION_LENGTH - sync with aztec-nr txe_oracles and TXE",
    );

    let (raw_array_storage, event_lengths, query_length) =
        get_private_events_oracle(selector, contract_address, scope);

    assert(
        query_length <= MAX_PRIVATE_EVENTS_PER_TXE_QUERY,
        "TXE query_length exceeds MAX_PRIVATE_EVENTS_PER_TXE_QUERY — sync constants with aztec-nr txe_oracles",
    );

    let mut events = BoundedVec::new();
    for i in 0..query_length {
        let len = event_lengths[i];
        assert(
            len <= MAX_EVENT_SERIALIZATION_LENGTH,
            "TXE event payload length exceeds MAX_EVENT_SERIALIZATION_LENGTH — sync constants with aztec-nr txe_oracles",
        );
        events.push(BoundedVec::from_parts(raw_array_storage[i], len));
    }
    events
}

/// Asserts the last transaction emitted exactly one `EscrowDetailsLogContent` private event to `recipient` from `logic`.
pub unconstrained fn assert_escrow_details_private_event(
    logic: AztecAddress,
    recipient: AztecAddress,
    expected_escrow: AztecAddress,
    expected_secret_key: Field,
) {
    let selector = EscrowDetailsLogContent::get_event_type_id();
    let events = get_private_events_from_last_tx(selector, logic, recipient);
    assert_eq(events.len(), 1);

    let payload = events.get(0);
    let expected =
        EscrowDetailsLogContent { escrow: expected_escrow, secret_key: expected_secret_key };
    let serialized = expected.serialize();
    assert_eq(payload.len(), serialized.len());
    for i in 0..serialized.len() {
        assert_eq(payload.get(i), serialized[i]);
    }
}
