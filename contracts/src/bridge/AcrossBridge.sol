// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAcrossBridge} from "../interfaces/IAcrossBridge.sol";

/// @dev Minimal interface for Across SpokePool
interface ISpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;
}

/// @title AcrossBridge
/// @notice Wraps the Across SpokePool to bridge USDC from Unichain to Arbitrum.
contract AcrossBridge is IAcrossBridge {
    using SafeERC20 for IERC20;

    ISpokePool public immutable spokePool;
    IERC20 public immutable usdc;

    /// @notice Default max relayer fee (0.1%)
    uint256 public constant DEFAULT_MAX_FEE_PCT = 1e15;

    uint256 private depositCounter;

    constructor(address _spokePool, address _usdc) {
        spokePool = ISpokePool(_spokePool);
        usdc = IERC20(_usdc);
    }

    function bridgeUSDC(
        uint256 amount,
        uint256 destinationChainId,
        address recipient,
        uint256 maxRelayerFeePct
    ) external override returns (bytes32 depositId) {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.approve(address(spokePool), amount);

        // Across fills at (amount - relayerFee). We accept up to maxRelayerFeePct slippage.
        uint256 outputAmount = amount - (amount * maxRelayerFeePct / 1e18);

        spokePool.depositV3(
            msg.sender,                          // depositor
            recipient,                           // recipient on destination
            address(usdc),                       // inputToken
            address(usdc),                       // outputToken (USDC on dest)
            amount,
            outputAmount,
            destinationChainId,
            address(0),                          // no exclusive relayer
            uint32(block.timestamp),             // quoteTimestamp
            uint32(block.timestamp + 3 hours),   // fillDeadline
            0,                                   // exclusivityDeadline
            ""                                   // no message
        );

        depositId = bytes32(++depositCounter);
        emit BridgeInitiated(bytes32(0), amount, destinationChainId, recipient);
    }

    function estimateBridgeFee(
        uint256 amount,
        uint256 /*destinationChainId*/
    ) external pure override returns (uint256 feePct) {
        // Across fees are typically 0.05–0.1% for USDC
        // TODO: query Across API for live fee quote
        return DEFAULT_MAX_FEE_PCT;
    }
}
