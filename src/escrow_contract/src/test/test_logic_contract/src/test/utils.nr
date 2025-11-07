use crate::TestLogic;
use aztec::{
    protocol_types::{
        address::AztecAddress,
        point::Point,
        public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM},
    },
    test::helpers::test_environment::TestEnvironment,
};
use escrow_contract::library::logic::MasterSecretKeys;

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

pub unconstrained fn get_test_vector() -> (PublicKeys, MasterSecretKeys, PublicKeys, MasterSecretKeys) {
    // secret keys derived using 1 as the seed
    let master_secret_keys_1 = MasterSecretKeys {
        nsk_m: 0x1c46232974b84af1ea0f3f8e02d68b205fa0fd765839bdd298d270c6f4d87190,
        ivsk_m: 0x23077d282aa597e7a1c6ffb4a1069cffd9743e861451076740cf42cb632fec84,
        ovsk_m: 0x0fd5dc80151e24e20e402fa82437be7483431347ca4aabde674cdb12598d0fc0,
        tsk_m: 0x0d104e3f086a9c3127b4152bac929180c21c06f9539b62843f4971753dd4ecf9,
    };

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

    // secret keys derived using string "RANDOM_SECRET_KEY" left-padded to 32 bytes with spaces as the seed:
    // 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559
    let master_secret_keys_2 = MasterSecretKeys {
        nsk_m: 0x0e9600b209142cfe453ee5082e0eb5916b381f81a1967556afe1049c87cbb2ae,
        ivsk_m: 0x01243994b0481f12305a17f6f12ed689e38c62d116efa1e2ff61718459f1d9b3,
        ovsk_m: 0x14958e327b2cbdfd7c18add0d5fc376e533f9ee47f18f47259c862a0429deaa4,
        tsk_m: 0x23c16c7e7fba57703aaf07ba75076c74d93747f2610e28689350b5e2f9061417,
    };

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

    (public_keys_1, master_secret_keys_1, public_keys_2, master_secret_keys_2)
}
