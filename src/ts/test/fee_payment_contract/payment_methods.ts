import type { FeePaymentMethod } from '@aztec/entrypoints/interfaces';
import { ExecutionPayload } from '@aztec/entrypoints/payload';
import { Fr } from '@aztec/foundation/fields';
import { AztecAddress } from '@aztec/stdlib/aztec-address';
import { GasSettings } from '@aztec/stdlib/gas';
import type { AccountWallet, IntentAction } from '@aztec/aztec.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { FPCContract } from '@aztec/noir-contracts.js/FPC';

// Fee Payment hook
export class FPCPayment implements FeePaymentMethod {

  constructor(
    protected paymentContract: FPCContract,
    protected paymentToken: TokenContract,
    protected wallet: AccountWallet,
    protected isPrivate: boolean
  ) { }

  getAsset(): Promise<AztecAddress> {
    return Promise.resolve(this.paymentToken.address);
  }

  getFeePayer(): Promise<AztecAddress> {
    return Promise.resolve(this.paymentContract.address);
  }

  async getExecutionPayload(gasSettings: GasSettings): Promise<ExecutionPayload> {
    const nonce = Fr.random();
    const maxFee = gasSettings.getFeeLimit();
    console.log("Max fee:", maxFee);

    // If sponsor is private, create private authwit for the `transfer_private_to_public` method.
    if (this.isPrivate) {
      const action = this.paymentToken.methods.transfer_private_to_public(this.wallet.getAddress(), this.paymentContract.address, maxFee.toNumber(), nonce);

      const intent: IntentAction = {
        caller: this.paymentContract.address,
        action,
      };
      const privateWitness = await this.wallet.createAuthWit(intent);

      // Return authwit along with call to `fee_entrypoint_private`
      return new ExecutionPayload(
        [
          ...(await this.paymentContract.methods.fee_entrypoint_private(maxFee.toNumber(), nonce).request()).calls
        ],
        [privateWitness],
        [],
      );
    } else {
      // If sponsor is public, create public authwit for the `transfer_public_to_public` method.
      const setPublicAuthWitInteraction = await this.wallet.setPublicAuthWit(
        {
          caller: this.paymentContract.address,
          action: this.paymentToken.methods.transfer_public_to_public(this.wallet.getAddress(), this.paymentContract, maxFee.toNumber(), nonce)
        },
        true,
      );

      // Return authwit along with call to `fee_entrypoint_public`
      return new ExecutionPayload(
        [
          ...(await setPublicAuthWitInteraction.request()).calls,
          ...(await this.paymentContract.methods.fee_entrypoint_public(maxFee.toNumber(), nonce).request()).calls
        ],
        [],
        [],
      );
    }
  }
}

