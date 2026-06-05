import { createWalletClient, http, encodeAbiParameters, keccak256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { HedgeInstruction } from "./types";

/// @notice Sign a HedgeInstruction using EIP-191 personal_sign.
///         The on-chain HedgeInstructionVerifier uses the same encoding.
export async function signInstruction(
  instruction: HedgeInstruction,
  privateKey: `0x${string}`
): Promise<`0x${string}`> {
  const account = privateKeyToAccount(privateKey);

  const encoded = encodeAbiParameters(
    [
      { type: "bytes32" },  // poolId
      { type: "int256" },   // targetNotional
      { type: "uint256" },  // maxSlippageBps
      { type: "uint256" },  // deadline
      { type: "uint256" },  // nonce
    ],
    [
      instruction.poolId,
      instruction.targetNotional,
      instruction.maxSlippageBps,
      instruction.deadline,
      instruction.nonce,
    ]
  );

  const hash = keccak256(encoded);
  // personal_sign prepends "\x19Ethereum Signed Message:\n32"
  const signature = await account.signMessage({ message: { raw: hash } });
  return signature;
}
