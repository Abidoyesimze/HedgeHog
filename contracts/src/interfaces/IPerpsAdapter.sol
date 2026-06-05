// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct PositionState {
    bytes32 positionId;
    int256 size;           // positive = long, negative = short (in USD)
    uint256 entryPrice;    // in 1e18 USD per ETH
    int256 unrealizedPnl;  // in USDC (1e6)
    uint256 collateral;    // USDC collateral backing this position (1e6)
}

interface IPerpsAdapter {
    event PositionOpened(bytes32 indexed positionId, int256 size, uint256 entryPrice);
    event PositionModified(bytes32 indexed positionId, int256 newSize);
    event PositionClosed(bytes32 indexed positionId, int256 realizedPnl);

    /// @notice Open a new position; size negative = short ETH
    function openPosition(
        int256 size,
        uint256 collateralAmount,
        uint256 maxSlippageBps
    ) external returns (bytes32 positionId);

    /// @notice Modify an existing position to a new size
    function modifyPosition(
        bytes32 positionId,
        int256 newSize,
        uint256 maxSlippageBps
    ) external;

    /// @notice Close a position fully and return realized P&L in USDC
    function closePosition(
        bytes32 positionId,
        uint256 maxSlippageBps
    ) external returns (int256 realizedPnl);

    /// @notice Return current state of a position
    function getPosition(bytes32 positionId) external view returns (PositionState memory);
}
