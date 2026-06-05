// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice GMX v2 order types (subset used by Hedgehog)
library Order {
    enum OrderType {
        MarketSwap,         // 0
        LimitSwap,          // 1
        MarketIncrease,     // 2
        LimitIncrease,      // 3
        MarketDecrease,     // 4
        LimitDecrease,      // 5
        StopLossDecrease,   // 6
        Liquidation         // 7
    }

    enum DecreasePositionSwapType {
        NoSwap,
        SwapPnlTokenToCollateralToken,
        SwapCollateralTokenToPnlToken
    }
}

struct CreateOrderParamsAddresses {
    address receiver;
    address cancellationReceiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address initialCollateralToken;
    address[] swapPath;
}

struct CreateOrderParamsNumbers {
    uint256 sizeDeltaUsd;
    uint256 initialCollateralDeltaAmount;
    uint256 triggerPrice;
    uint256 acceptablePrice;
    uint256 executionFee;
    uint256 callbackGasLimit;
    uint256 minOutputAmount;
    uint256 validFromTime;
}

struct CreateOrderParams {
    CreateOrderParamsAddresses addresses;
    CreateOrderParamsNumbers numbers;
    Order.OrderType orderType;
    Order.DecreasePositionSwapType decreasePositionSwapType;
    bool isLong;
    bool shouldUnwrapNativeToken;
    bool autoCancel;
    bytes32 referralCode;
}

/// @notice GMX v2 position data returned by Reader
struct PositionInfo {
    PositionData position;
    PositionFees fees;
}

struct PositionData {
    PositionAddresses addresses;
    PositionNumbers numbers;
    PositionFlags flags;
}

struct PositionAddresses {
    address account;
    address market;
    address collateralToken;
}

struct PositionNumbers {
    uint256 sizeInUsd;
    uint256 sizeInTokens;
    uint256 collateralAmount;
    uint256 borrowingFactor;
    uint256 fundingFeeAmountPerSize;
    uint256 longTokenClaimableFundingAmountPerSize;
    uint256 shortTokenClaimableFundingAmountPerSize;
    uint256 increasedAtTime;
    uint256 decreasedAtTime;
}

struct PositionFlags {
    bool isLong;
}

struct PositionFees {
    PositionReferralFees referral;
    PositionFundingFees funding;
    PositionBorrowingFees borrowing;
    PositionUiFees ui;
    int256 latestLongTokenFundingFeeAmountPerSize;
    int256 latestShortTokenFundingFeeAmountPerSize;
    bool hasPendingLongTokenFundingFee;
    bool hasPendingShortTokenFundingFee;
    uint256 borrowingFeeUsd;
    uint256 borrowingFeeAmount;
    uint256 borrowingFeeReceiverFactor;
    uint256 borrowingFeeAmountForFeeReceiver;
    uint256 positionFeeFactor;
    uint256 protocolFeeAmount;
    uint256 positionFeeReceiverFactor;
    uint256 feeReceiverAmount;
    uint256 feeAmountForPool;
    uint256 positionFeeAmountForPool;
    uint256 positionFeeAmount;
    uint256 totalCostAmountExcludingFunding;
    uint256 totalCostAmount;
}

struct PositionReferralFees { address referralCode; uint256 affiliateRewardAmount; }
struct PositionFundingFees { uint256 fundingFeeAmount; uint256 claimableLongTokenAmount; uint256 claimableShortTokenAmount; uint256 latestFundingFeeAmountPerSize; uint256 latestLongTokenClaimableFundingAmountPerSize; uint256 latestShortTokenClaimableFundingAmountPerSize; }
struct PositionBorrowingFees { uint256 borrowingFeeUsd; uint256 borrowingFeeAmount; uint256 borrowingFeeReceiverFactor; uint256 borrowingFeeAmountForFeeReceiver; }
struct PositionUiFees { address uiFeeReceiver; uint256 uiFeeReceiverFactor; uint256 uiFeeAmount; }

/// @notice Minimal interface for GMX v2 ExchangeRouter
interface IGmxExchangeRouter {
    function createOrder(CreateOrderParams calldata params) external payable returns (bytes32 key);
    function cancelOrder(bytes32 key) external;
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external;
}

/// @notice Minimal interface for GMX v2 Reader
interface IGmxReader {
    function getPosition(address dataStore, bytes32 key) external view returns (PositionData memory);
    function getPositionInfo(
        address dataStore,
        address referralStorage,
        bytes32 positionKey,
        MarketUtils.MarketPrices memory prices,
        uint256 sizeDeltaUsd,
        address uiFeeReceiver,
        bool useMaxSizeDeltaUsd
    ) external view returns (PositionInfo memory);
}

/// @notice Minimal interface for GMX v2 DataStore
interface IGmxDataStore {
    function getBytes32(bytes32 key) external view returns (bytes32);
    function getUint(bytes32 key) external view returns (uint256);
}

/// @notice GMX v2 market price struct used by Reader
library MarketUtils {
    struct MarketPrices {
        Price.Props indexTokenPrice;
        Price.Props longTokenPrice;
        Price.Props shortTokenPrice;
    }
}

library Price {
    struct Props {
        uint256 min;
        uint256 max;
    }
}
