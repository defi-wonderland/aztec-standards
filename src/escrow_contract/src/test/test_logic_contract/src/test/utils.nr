use crate::TestLogic;
use aztec::{
    protocol::{
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

    let npk_x_1: Field = 0x073efcdf630f4f8ee645d078cb359d53ec412131b056741c2f5b3c7271e37b4c;
    let npk_y_1: Field = 0x0b9b360e7c2734cfb8389b1544166e9dab63911a7540c1c11d1425c9cfb22af9;
    let ivpk_x_1: Field = 0x2fe245e0b6069a5fb16362d5ba080e606aaf6289d2c8ab5d66321922683b0d93;
    let ivpk_y_1: Field = 0x07543b20ffb55e43effeec0c0f57b9cebda996b553edcd1eddfc1d56060175e3;
    let ovpk_x_1: Field = 0x14e40f7584fcf552b05e9a38f907cb2c7d81ad2784c651ecec35fd7599be92e2;
    let ovpk_y_1: Field = 0x1004b3b0b6fbba71142e08365826625c4743a895575035efd24623846351f1a1;
    let tpk_x_1: Field = 0x2077db9a4644bfd63663f25b5fed3f368d3104f4562cbf647b5386a0a926fc5e;
    let tpk_y_1: Field = 0x08c4fa4f4b9f92b1b281fb280e91abe07e44efc227baed44fed02b9f6b0080e5;

    let public_keys_1 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_1, y: npk_y_1, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_1, y: ivpk_y_1, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_1, y: ovpk_y_1, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_1, y: tpk_y_1, is_infinite: false } },
    };

    // Secret key 2: string "RANDOM_SECRET_KEY" left-padded to 32 bytes with spaces
    // 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559
    let secret_key_2: Field = 0x20202020202020202020202020202052414e444f4d5f5345435245545f4b4559;

    let npk_x_2: Field = 0x007a02f4868b987e2267e32e14ac76e5a0bf47443c94ecd5a065da0f67ee8cd0;
    let npk_y_2: Field = 0x02ee669facb33f0935c5c12dcde6fcb3639bcf3bc2a4cdffb229bb503c3a273d;
    let ivpk_x_2: Field = 0x127e621cbfe09877e623eef3a5025897823f29532fb19fd79de12b260ab8100b;
    let ivpk_y_2: Field = 0x2f08e3c775d0b734a0da792b463fdee05b0315aaea53ec3447e7e2fa96106c3d;
    let ovpk_x_2: Field = 0x1621e7df33440c75183177fe37b32aabfdecd07b188df03ea2e6c234fdf4e61c;
    let ovpk_y_2: Field = 0x12cf59e9555b91462efa3008aa823b1ec2c456f9d62b66cbc36eecbaf7936826;
    let tpk_x_2: Field = 0x1607264012a2510f3b1ca3a6da5d01c288490fbe5d37bb3719a18a0eb929bdf9;
    let tpk_y_2: Field = 0x1f57c09b4218e304a0a336f29c6f7ecc27e4019c58a2a6b29a114e609ad927f9;

    let public_keys_2 = PublicKeys {
        npk_m: NpkM { inner: Point { x: npk_x_2, y: npk_y_2, is_infinite: false } },
        ivpk_m: IvpkM { inner: Point { x: ivpk_x_2, y: ivpk_y_2, is_infinite: false } },
        ovpk_m: OvpkM { inner: Point { x: ovpk_x_2, y: ovpk_y_2, is_infinite: false } },
        tpk_m: TpkM { inner: Point { x: tpk_x_2, y: tpk_y_2, is_infinite: false } },
    };

    (public_keys_1, secret_key_1, public_keys_2, secret_key_2)
}
