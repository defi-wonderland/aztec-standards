// aztec library
use aztec::{
    messages::logs::{event::to_encrypted_private_event_message, utils::prefix_with_tag},
    oracle::get_contract_instance::get_contract_instance,
    prelude::{AztecAddress, PrivateContext},
    protocol_types::{
        constants::GENERATOR_INDEX__EVENT_COMMITMENT,
        contract_instance::ContractInstance,
        hash::poseidon2_hash_with_separator,
        public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM},
        traits::{Serialize, ToField},
    },
};
// standard library
use std::embedded_curve_ops::{EmbeddedCurvePoint, EmbeddedCurveScalar, fixed_base_scalar_mul};
// escrow contract
use crate::Escrow;
// escrow details event
use crate::types::escrow_details_event::EscrowDetailsLogContent;

/** ==========================================================
 * =================== LOGIC LIBRARIES =======================
 * ======================================================== */

/// @notice Verifies that the keys correspond to the escrow address and that the escrow instance data is correct.
/// @dev Reverts if the data is not correct.
/// @param context The private context
/// @param escrow The address of the escrow
/// @param escrow_class_id The contract class id of the escrow contract
/// @param nsk_m The escrow nullifier secret key
/// @param ivsk_m The escrow incoming viewing key
/// @param ovsk_m The escrow outgoing viewing key
/// @param tsk_m The escrow transaction secret key
#[contract_library_method]
pub fn _check_escrow(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    escrow_class_id: Field,
    nsk_m: Field,
    ivsk_m: Field,
    ovsk_m: Field,
    tsk_m: Field,
) {
    // Get the escrow instance
    let escrow_instance: ContractInstance = get_contract_instance(escrow);

    // Compute the public keys from the secret keys
    let computed_public_keys: PublicKeys =
        _secret_keys_to_public_keys(nsk_m, ivsk_m, ovsk_m, tsk_m);

    // Check the public keys are computed correctly
    assert_eq(computed_public_keys, escrow_instance.public_keys, "Escrow public keys mismatch");

    // Force the initialization hash and deployer to be null
    assert_eq(escrow_instance.initialization_hash, 0, "Escrow initialization hash should be null");
    assert_eq(escrow_instance.deployer.to_field(), 0, "Escrow deployer should be null");

    // Check the class id is correct
    assert_eq(
        escrow_instance.contract_class_id.to_field(),
        escrow_class_id,
        "Escrow class id mismatch",
    );

    // Force the salt to be equal to the address of the logic contract (this contract)
    assert_eq(escrow_instance.salt, context.this_address().to_field(), "Escrow salt mismatch");
}

/// @notice Shares the escrow details needed to find and use the escrow contract
/// @dev Emits a private log with the escrow details
/// @param context The private context
/// @param account The address of the account that will use the escrow
/// @param escrow The address of the escrow
/// @param nsk_m The escrow nullifier secret key
/// @param ivsk_m The escrow incoming viewing key
/// @param ovsk_m The escrow outgoing viewing key
/// @param tsk_m The escrow transaction secret key
#[contract_library_method]
pub fn _share_escrow(
    context: &mut PrivateContext,
    account: AztecAddress,
    escrow: AztecAddress,
    nsk_m: Field,
    ivsk_m: Field,
    ovsk_m: Field,
    tsk_m: Field,
) {
    let event_struct = EscrowDetailsLogContent { escrow, nsk_m, ivsk_m, ovsk_m, tsk_m };

    // Implementation from aztec-packages event_interface.nr in v1.2.1
    let (ciphertext, randomness) = to_encrypted_private_event_message(event_struct, account);
    let serialized_event_with_randomness = [randomness].concat(event_struct.serialize());
    let event_commitment = poseidon2_hash_with_separator(
        serialized_event_with_randomness,
        GENERATOR_INDEX__EVENT_COMMITMENT,
    );
    context.push_nullifier(event_commitment);
    let log_content = prefix_with_tag(ciphertext, context.msg_sender(), account);
    context.emit_private_log(log_content, log_content.len());
}

/// @notice Withdraws an amount of tokens from the provided escrow.
/// @param escrow The address of the escrow
/// @param account The address of the account that will receive the tokens
/// @param token The address of the token
/// @param amount The amount of tokens to withdraw from the escrow
#[contract_library_method]
pub fn _withdraw(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    account: AztecAddress,
    token: AztecAddress,
    amount: u128,
) {
    Escrow::at(escrow).withdraw(token, amount, account).call(context);
}

/// @notice Withdraws an NFT from the provided escrow.
/// @param escrow The address of the escrow
/// @param account The address of the account that will receive the NFT
/// @param nft The address of the NFT contract
/// @param token_id The id of the token to withdraw from the escrow
#[contract_library_method]
pub fn _withdraw_nft(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    account: AztecAddress,
    nft: AztecAddress,
    token_id: Field,
) {
    Escrow::at(escrow).withdraw_nft(nft, token_id, account).call(context);
}

/// @notice Derives public keys from secret keys.
/// @param nsk_m Master Nullifier Secret Key
/// @param ivsk_m Incoming Viewing Key
/// @param ovsk_m Outgoing Viewing Key
/// @param tsk_m Transaction Secret Key
/// @return PublicKeys containing the derived public keys.
#[contract_library_method]
pub fn _secret_keys_to_public_keys(
    nsk_m: Field,
    ivsk_m: Field,
    ovsk_m: Field,
    tsk_m: Field,
) -> PublicKeys {
    let npk_m: EmbeddedCurvePoint = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(nsk_m));
    let ivpk_m: EmbeddedCurvePoint = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ivsk_m));
    let ovpk_m: EmbeddedCurvePoint = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ovsk_m));
    let tpk_m: EmbeddedCurvePoint = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(tsk_m));

    PublicKeys {
        npk_m: NpkM { inner: npk_m },
        ivpk_m: IvpkM { inner: ivpk_m },
        ovpk_m: OvpkM { inner: ovpk_m },
        tpk_m: TpkM { inner: tpk_m },
    }
}
