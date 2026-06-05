// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPerpsAdapter, PositionState} from "../interfaces/IPerpsAdapter.sol";

/// @title MockAdapter
/// @notice Test/demo adapter — records positions in memory, no real perps DEX calls.
contract MockAdapter is IPerpsAdapter {
    mapping(bytes32 => PositionState) private positions;
    uint256 private nextId;

    function openPosition(
        int256 size,
        uint256 collateralAmount,
        uint256 maxSlippageBps
    ) external override returns (bytes32 positionId) {
        positionId = bytes32(++nextId);
        positions[positionId] = PositionState({
            positionId: positionId,
            size: size,
            entryPrice: 2000e18,  // mock price $2000
            unrealizedPnl: 0,
            collateral: collateralAmount
        });
        emit PositionOpened(positionId, size, 2000e18);
    }

    function modifyPosition(
        bytes32 positionId,
        int256 newSize,
        uint256
    ) external override {
        require(positions[positionId].positionId == positionId, "MockAdapter: unknown position");
        positions[positionId].size = newSize;
        emit PositionModified(positionId, newSize);
    }

    function closePosition(
        bytes32 positionId,
        uint256
    ) external override returns (int256 realizedPnl) {
        require(positions[positionId].positionId == positionId, "MockAdapter: unknown position");
        realizedPnl = positions[positionId].unrealizedPnl;
        delete positions[positionId];
        emit PositionClosed(positionId, realizedPnl);
    }

    function getPosition(bytes32 positionId) external view override returns (PositionState memory) {
        return positions[positionId];
    }
}
