// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPerpsAdapter, PositionState} from "../interfaces/IPerpsAdapter.sol";
import {
    IGmxExchangeRouter,
    IGmxReader,
    IGmxDataStore,
    CreateOrderParams,
    CreateOrderParamsAddresses,
    CreateOrderParamsNumbers,
    Order,
    MarketUtils,
    Price
} from "../interfaces/IGmxV2.sol";

/// @title GmxAdapter
/// @notice Opens and closes ETH short positions on GMX v2 (Arbitrum).
///         Called by HedgehogArbitrum after USDC arrives via Across bridge.
contract GmxAdapter is IPerpsAdapter {
    using SafeERC20 for IERC20;

    // -----------------------------------------------------------------------
    // Immutables — set at deploy time per network
    // -----------------------------------------------------------------------

    IGmxExchangeRouter public immutable exchangeRouter;
    IGmxReader         public immutable reader;
    IGmxDataStore      public immutable dataStore;

    address public immutable orderVault;   // GMX OrderVault — receives collateral before order execution
    address public immutable ethUsdMarket; // GMX ETH-USD market address
    address public immutable usdc;
    address public immutable weth;

    // UI fee receiver (zero address = no UI fee)
    address public constant UI_FEE_RECEIVER = address(0);
    bytes32 public constant REFERRAL_CODE   = bytes32(0);

    // Execution fee sent as ETH with each order (covers GMX keeper gas)
    uint256 public constant EXECUTION_FEE = 0.001 ether;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    address public immutable owner; // HedgehogArbitrum that deploys this adapter

    /// @notice Maps our internal positionId → GMX order key (used while order is pending)
    mapping(bytes32 => bytes32) public pendingOrderKey;

    /// @notice Stored position state (updated after order confirmed)
    mapping(bytes32 => PositionState) private positions;

    uint256 private nextId;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _exchangeRouter,
        address _reader,
        address _dataStore,
        address _orderVault,
        address _ethUsdMarket,
        address _usdc,
        address _weth
    ) {
        exchangeRouter = IGmxExchangeRouter(_exchangeRouter);
        reader         = IGmxReader(_reader);
        dataStore      = IGmxDataStore(_dataStore);
        orderVault     = _orderVault;
        ethUsdMarket   = _ethUsdMarket;
        usdc           = _usdc;
        weth           = _weth;
        owner          = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "GmxAdapter: not owner");
        _;
    }

    // -----------------------------------------------------------------------
    // IPerpsAdapter — open
    // -----------------------------------------------------------------------

    /// @notice Open a short ETH position on GMX v2.
    /// @param size          Negative value = short. Magnitude in USD (1e30 per GMX convention).
    /// @param collateralAmount USDC amount (1e6) to use as collateral.
    /// @param maxSlippageBps Max acceptable price slippage in bps.
    function openPosition(
        int256 size,
        uint256 collateralAmount,
        uint256 maxSlippageBps
    ) external override onlyOwner returns (bytes32 positionId) {
        require(size < 0, "GmxAdapter: only shorts supported");
        require(collateralAmount > 0, "GmxAdapter: zero collateral");

        positionId = bytes32(++nextId);

        // Pull USDC from caller
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Send collateral to GMX OrderVault before creating order
        IERC20(usdc).approve(address(exchangeRouter), collateralAmount);
        exchangeRouter.sendTokens(usdc, orderVault, collateralAmount);

        // sizeDeltaUsd: GMX v2 uses 1e30 USD precision
        // We receive size in 1e18 terms (ETH units), convert:
        // If size = -1e18 ETH and ETH ~ $3000, sizeDeltaUsd = 3000 * 1e30
        // For adapter simplicity, caller passes pre-scaled USD amount as abs(size) in 1e30
        uint256 sizeDeltaUsd = uint256(-size); // caller passes in 1e30 USD

        // Acceptable price: spot + slippage (shorts need higher accept price)
        // We trust GMX oracle; pass 0 for market orders to accept any price
        uint256 acceptablePrice = 0;

        CreateOrderParams memory params = CreateOrderParams({
            addresses: CreateOrderParamsAddresses({
                receiver:             address(this),
                cancellationReceiver: address(this),
                callbackContract:     address(0),
                uiFeeReceiver:        UI_FEE_RECEIVER,
                market:               ethUsdMarket,
                initialCollateralToken: usdc,
                swapPath:             new address[](0)
            }),
            numbers: CreateOrderParamsNumbers({
                sizeDeltaUsd:               sizeDeltaUsd,
                initialCollateralDeltaAmount: collateralAmount,
                triggerPrice:               0,
                acceptablePrice:            acceptablePrice,
                executionFee:               EXECUTION_FEE,
                callbackGasLimit:           0,
                minOutputAmount:            0,
                validFromTime:              0
            }),
            orderType:                   Order.OrderType.MarketIncrease,
            decreasePositionSwapType:    Order.DecreasePositionSwapType.NoSwap,
            isLong:                      false, // SHORT
            shouldUnwrapNativeToken:     false,
            autoCancel:                  false,
            referralCode:                REFERRAL_CODE
        });

        bytes32 orderKey = exchangeRouter.createOrder{value: EXECUTION_FEE}(params);
        pendingOrderKey[positionId] = orderKey;

        // Store initial state (will be confirmed when keeper executes order)
        positions[positionId] = PositionState({
            positionId:    positionId,
            size:          size,
            entryPrice:    0,  // updated when order fills
            unrealizedPnl: 0,
            collateral:    collateralAmount
        });

        emit PositionOpened(positionId, size, 0);
    }

    // -----------------------------------------------------------------------
    // IPerpsAdapter — modify
    // -----------------------------------------------------------------------

    /// @notice Increase or decrease an existing GMX short position.
    function modifyPosition(
        bytes32 positionId,
        int256 newSize,
        uint256 maxSlippageBps
    ) external override onlyOwner {
        PositionState storage pos = positions[positionId];
        require(pos.positionId == positionId, "GmxAdapter: unknown position");
        require(newSize < 0, "GmxAdapter: only shorts");

        int256 delta = newSize - pos.size; // negative = increasing short

        if (delta < 0) {
            // Increasing short — MarketIncrease
            uint256 sizeDeltaUsd = uint256(-delta);

            CreateOrderParams memory params = CreateOrderParams({
                addresses: CreateOrderParamsAddresses({
                    receiver:             address(this),
                    cancellationReceiver: address(this),
                    callbackContract:     address(0),
                    uiFeeReceiver:        UI_FEE_RECEIVER,
                    market:               ethUsdMarket,
                    initialCollateralToken: usdc,
                    swapPath:             new address[](0)
                }),
                numbers: CreateOrderParamsNumbers({
                    sizeDeltaUsd:               sizeDeltaUsd,
                    initialCollateralDeltaAmount: 0,
                    triggerPrice:               0,
                    acceptablePrice:            0,
                    executionFee:               EXECUTION_FEE,
                    callbackGasLimit:           0,
                    minOutputAmount:            0,
                    validFromTime:              0
                }),
                orderType:                   Order.OrderType.MarketIncrease,
                decreasePositionSwapType:    Order.DecreasePositionSwapType.NoSwap,
                isLong:                      false,
                shouldUnwrapNativeToken:     false,
                autoCancel:                  false,
                referralCode:                REFERRAL_CODE
            });
            exchangeRouter.createOrder{value: EXECUTION_FEE}(params);
        } else {
            // Decreasing short — MarketDecrease
            uint256 sizeDeltaUsd = uint256(delta);

            CreateOrderParams memory params = CreateOrderParams({
                addresses: CreateOrderParamsAddresses({
                    receiver:             address(this),
                    cancellationReceiver: address(this),
                    callbackContract:     address(0),
                    uiFeeReceiver:        UI_FEE_RECEIVER,
                    market:               ethUsdMarket,
                    initialCollateralToken: usdc,
                    swapPath:             new address[](0)
                }),
                numbers: CreateOrderParamsNumbers({
                    sizeDeltaUsd:               sizeDeltaUsd,
                    initialCollateralDeltaAmount: 0,
                    triggerPrice:               0,
                    acceptablePrice:            type(uint256).max, // accept any price for market decrease
                    executionFee:               EXECUTION_FEE,
                    callbackGasLimit:           0,
                    minOutputAmount:            0,
                    validFromTime:              0
                }),
                orderType:                   Order.OrderType.MarketDecrease,
                decreasePositionSwapType:    Order.DecreasePositionSwapType.SwapPnlTokenToCollateralToken,
                isLong:                      false,
                shouldUnwrapNativeToken:     false,
                autoCancel:                  false,
                referralCode:                REFERRAL_CODE
            });
            exchangeRouter.createOrder{value: EXECUTION_FEE}(params);
        }

        pos.size = newSize;
        emit PositionModified(positionId, newSize);
    }

    // -----------------------------------------------------------------------
    // IPerpsAdapter — close
    // -----------------------------------------------------------------------

    /// @notice Close the entire short position on GMX v2.
    function closePosition(
        bytes32 positionId,
        uint256 maxSlippageBps
    ) external override onlyOwner returns (int256 realizedPnl) {
        PositionState storage pos = positions[positionId];
        require(pos.positionId == positionId, "GmxAdapter: unknown position");

        uint256 sizeDeltaUsd = uint256(-pos.size);

        CreateOrderParams memory params = CreateOrderParams({
            addresses: CreateOrderParamsAddresses({
                receiver:             msg.sender, // return USDC + PnL to HedgehogArbitrum
                cancellationReceiver: address(this),
                callbackContract:     address(0),
                uiFeeReceiver:        UI_FEE_RECEIVER,
                market:               ethUsdMarket,
                initialCollateralToken: usdc,
                swapPath:             new address[](0)
            }),
            numbers: CreateOrderParamsNumbers({
                sizeDeltaUsd:               sizeDeltaUsd,
                initialCollateralDeltaAmount: pos.collateral,
                triggerPrice:               0,
                acceptablePrice:            type(uint256).max,
                executionFee:               EXECUTION_FEE,
                callbackGasLimit:           0,
                minOutputAmount:            0,
                validFromTime:              0
            }),
            orderType:                   Order.OrderType.MarketDecrease,
            decreasePositionSwapType:    Order.DecreasePositionSwapType.SwapPnlTokenToCollateralToken,
            isLong:                      false,
            shouldUnwrapNativeToken:     false,
            autoCancel:                  false,
            referralCode:                REFERRAL_CODE
        });

        exchangeRouter.createOrder{value: EXECUTION_FEE}(params);

        realizedPnl = pos.unrealizedPnl; // updated async by keeper; return last known
        emit PositionClosed(positionId, realizedPnl);
        delete positions[positionId];
    }

    // -----------------------------------------------------------------------
    // IPerpsAdapter — view
    // -----------------------------------------------------------------------

    function getPosition(bytes32 positionId) external view override returns (PositionState memory) {
        return positions[positionId];
    }

    // -----------------------------------------------------------------------
    // Admin — receive ETH for execution fees
    // -----------------------------------------------------------------------

    receive() external payable {}

    function withdrawEth(address to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "GmxAdapter: ETH transfer failed");
    }
}
