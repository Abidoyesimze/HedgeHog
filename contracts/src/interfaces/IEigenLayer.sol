// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal EigenLayer interfaces needed by HedgehogServiceManager.
///         Full middleware: https://github.com/Layr-Labs/eigenlayer-middleware

interface ISignatureUtils {
    struct SignatureWithSaltAndExpiry {
        bytes  signature;
        bytes32 salt;
        uint256 expiry;
    }
}

interface IAVSDirectory {
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    function deregisterOperatorFromAVS(address operator) external;

    function updateAVSMetadataURI(string calldata metadataURI) external;

    function operatorSaltIsSpent(address operator, bytes32 salt) external view returns (bool);
}

interface IDelegationManager {
    function isOperator(address operator) external view returns (bool);
    function operatorDetails(address operator) external view returns (address, uint32, address);
}

interface IServiceManager {
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    function deregisterOperatorFromAVS(address operator) external;

    function getRestakeableStrategies() external view returns (address[] memory);

    function getOperatorRestakedStrategies(address operator) external view returns (address[] memory);

    function avsDirectory() external view returns (address);
}
