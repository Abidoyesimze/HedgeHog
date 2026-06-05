// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {HedgeInstruction} from "../interfaces/IHedgeVault.sol";

/// @title HedgeInstructionVerifier
/// @notice Stateless library for verifying AVS operator signatures on HedgeInstructions.
library HedgeInstructionVerifier {
    using ECDSA for bytes32;

    function hashInstruction(HedgeInstruction calldata instruction) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            instruction.poolId,
            instruction.targetNotional,
            instruction.maxSlippageBps,
            instruction.deadline,
            instruction.nonce
        ));
    }

    function recoverSigner(
        HedgeInstruction calldata instruction,
        bytes calldata signature
    ) internal pure returns (address) {
        return hashInstruction(instruction)
            .toEthSignedMessageHash()
            .recover(signature);
    }

    function verify(
        HedgeInstruction calldata instruction,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        return recoverSigner(instruction, signature) == expectedSigner;
    }
}
