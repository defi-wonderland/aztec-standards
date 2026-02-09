use crate::TestLogic;
use aztec::{
    protocol_types::{
        address::AztecAddress,
        point::Point,
        public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM},
    },
    test::helpers::test_environment::TestEnvironment,
};

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

    let npk_x_1: Field = 0x0b6111daac402252e041933aad127a26c9851acb11ced405d8563435bb33e0b8;
    let npk_y_1: Field = 0x0ecf620002229630f89c4f06638c3155f7e331a98e3304d92f2b7e213250d3f6;
    let ivpk_x_1: Field = 0x228e3645559e65ec052b25919ca2e8e9b610fcc1b61490a2fd7fc335909b018e;
    let ivpk_y_1: Field = 0x01ebaf7375bbeff41e6a41271ba3be92081b188654c773a76205b49265bb423c;
    let ovpk_x_1: Field = 0x1be0ff304b9be7acedfdf137a5e369576a19246f181602f7f53ba3ec319e18c8;
    let ovpk_y_1: Field = 0x19660b865a39e2196cc0ab6c0b901c23a30d275b8ec8f7d327478b24bb8629bc;
    let tpk_x_1: Field = 0x1ec58e51af858e5aca8a6f4ec35016cf3df68154d87d0fc235bedf94d1418e7e;
    let tpk_y_1: Field = 0x0e76360c52a5695c666495a6094032a486c04cf71cc9cf997bf92b916bed1493;

    let public_keys_1 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_1, y: npk_y_1, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_1, y: ivpk_y_1, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_1, y: ovpk_y_1, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_1, y: tpk_y_1, is_infinite: false } },
    };

    // Secret key 2: string "RANDOM_SECRET_KEY" left-padded to 32 bytes with spaces
    // 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559
    let secret_key_2: Field = 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559;

    let npk_x_2: Field = 0x00ecf1384fa9a5acdaddcf0ca577d12d80309aab813dcf96ea79fad43f3daad9;
    let npk_y_2: Field = 0x24c81884aece11096a3058433339dd0180756c44b4372951f169c939f569f4fb;
    let ivpk_x_2: Field = 0x1d352885fed013e664fecb7cba4b2866f247616160d7b83218dfdba95302c16d;
    let ivpk_y_2: Field = 0x0c99f03d15323e6a59211db9ac5e81027671f8892030f06c9f541876974407ca;
    let ovpk_x_2: Field = 0x022d55fad39b3889ddecf7ab7634030c15da637e86e3ed550c8148076055e31a;
    let ovpk_y_2: Field = 0x27b58d54d8f22b769382eb8753181e3d56b0e2a247af7df7c79c28f01f168cc1;
    let tpk_x_2: Field = 0x2c3a360ec75935a2f3a12761bd764fe6fd97acaec5d085144795a05cbdf0b01b;
    let tpk_y_2: Field = 0x304512f4fad762bccf727a1cb5b1654211a6fdb7c09535faa1a786dd935bff55;

    let public_keys_2 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_2, y: npk_y_2, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_2, y: ivpk_y_2, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_2, y: ovpk_y_2, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_2, y: tpk_y_2, is_infinite: false } },
    };

    (public_keys_1, secret_key_1, public_keys_2, secret_key_2)
}
