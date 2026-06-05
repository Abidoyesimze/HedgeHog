// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {
    IServiceManager,
    IAVSDirectory,
    IDelegationManager,
    ISignatureUtils
} from "./interfaces/IEigenLayer.sol";

/// @title HedgehogServiceManager
/// @notice EigenLayer AVS service manager for the Hedgehog delta-neutral LP protocol.
///         Operators register here to be eligible to sign HedgeInstructions.
///         Full multi-operator path: extend EigenLayer's ServiceManagerBase and wire
///         BLSRegistryCoordinatorWithIndices for BLS aggregation (post-hackathon).
contract HedgehogServiceManager is IServiceManager, Ownable {
    using ECDSA for bytes32;

    // -----------------------------------------------------------------------
    // Immutables
    // -----------------------------------------------------------------------

    IAVSDirectory     public immutable avsDir;
    IDelegationManager public immutable delegation;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Operators registered to this AVS
    mapping(address => bool) public operators;

    /// @notice Maps operator → nonce for task response deduplication
    mapping(address => uint256) public operatorTaskNonce;

    string public metadataURI;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event OperatorRegistered(address indexed operator);
    event OperatorDeregistered(address indexed operator);
    event MetadataURIUpdated(string newURI);
    event HedgeTaskResponded(
        bytes32 indexed poolId,
        int256 targetNotional,
        address indexed operator,
        uint256 nonce
    );

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _avsDirectory, address _delegationManager) {
        avsDir     = IAVSDirectory(_avsDirectory);
        delegation = IDelegationManager(_delegationManager);
    }

    // -----------------------------------------------------------------------
    // IServiceManager
    // -----------------------------------------------------------------------

    /// @notice Register an EigenLayer operator to this AVS.
    ///         The operator must be registered in EigenLayer's DelegationManager first.
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external override {
        require(!operators[operator], "HedgehogSM: already registered");
        require(delegation.isOperator(operator), "HedgehogSM: not an EigenLayer operator");
        avsDir.registerOperatorToAVS(operator, operatorSignature);
        operators[operator] = true;
        emit OperatorRegistered(operator);
    }

    /// @notice Deregister an operator from this AVS.
    function deregisterOperatorFromAVS(address operator) external override {
        require(msg.sender == operator || msg.sender == owner(), "HedgehogSM: unauthorized");
        require(operators[operator], "HedgehogSM: not registered");
        avsDir.deregisterOperatorFromAVS(operator);
        operators[operator] = false;
        emit OperatorDeregistered(operator);
    }

    function getRestakeableStrategies() external pure override returns (address[] memory) {
        // For v1 hackathon: no strategy filtering. Any restaker can operate.
        return new address[](0);
    }

    function getOperatorRestakedStrategies(address) external pure override returns (address[] memory) {
        return new address[](0);
    }

    function avsDirectory() external view override returns (address) {
        return address(avsDir);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function updateMetadataURI(string calldata uri) external onlyOwner {
        metadataURI = uri;
        avsDir.updateAVSMetadataURI(uri);
        emit MetadataURIUpdated(uri);
    }

    // -----------------------------------------------------------------------
    // Operator task response logging (on-chain record of hedge decisions)
    // -----------------------------------------------------------------------

    /// @notice Emitted by the operator after signing and submitting a HedgeInstruction.
    ///         This is the on-chain record that proves the AVS responded to a task.
    function respondToHedgeTask(
        bytes32 poolId,
        int256 targetNotional,
        uint256 taskNonce,
        bytes calldata signature
    ) external {
        require(operators[msg.sender], "HedgehogSM: not a registered operator");
        require(taskNonce == operatorTaskNonce[msg.sender], "HedgehogSM: wrong nonce");
        operatorTaskNonce[msg.sender]++;

        // Verify the operator signed this task
        bytes32 taskHash = keccak256(abi.encode(poolId, targetNotional, taskNonce));
        address recovered = taskHash.toEthSignedMessageHash().recover(signature);
        require(recovered == msg.sender, "HedgehogSM: invalid signature");

        emit HedgeTaskResponded(poolId, targetNotional, msg.sender, taskNonce);
    }
}
