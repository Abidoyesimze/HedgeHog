// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAcrossBridge {
    event BridgeInitiated(
        bytes32 indexed poolId,
        uint256 amount,
        uint256 destinationChainId,
        address recipient
    );

    /// @notice Bridge USDC from this chain to a destination chain
    /// @param amount Amount of USDC (1e6) to bridge
    /// @param destinationChainId Target chain ID
    /// @param recipient Address to receive funds on destination chain
    /// @param maxRelayerFeePct Maximum relayer fee in 1e18 (e.g. 1e16 = 1%)
    function bridgeUSDC(
        uint256 amount,
        uint256 destinationChainId,
        address recipient,
        uint256 maxRelayerFeePct
    ) external returns (bytes32 depositId);

    /// @notice Estimate bridge fee for a given amount
    function estimateBridgeFee(
        uint256 amount,
        uint256 destinationChainId
    ) external view returns (uint256 feePct);
}
