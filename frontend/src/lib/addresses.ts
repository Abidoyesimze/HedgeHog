// Unichain Sepolia (1301)
export const UNICHAIN_ADDRESSES = {
  hedgeVault:  '0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C',
  hedgehogHook:'0x7F11fcE1603c806D14c8F7D35E7B0e4B785F02f9',
  acrossBridge:'0x1264e8ab9E98E2575856B831e606af43BAc0Fe65',
  usdc:        '0x31d0220469e10c4E71834a79b1f276d740d3768F',
} as const

// Arbitrum Sepolia (421614)
export const ARBITRUM_ADDRESSES = {
  hedgehogArbitrum: '0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C',
  mockAdapter:      '0x1264e8ab9E98E2575856B831e606af43BAc0Fe65',
  usdc:             '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
} as const

// Demo pool ID (keccak256 of pool key — update after pool is initialised on-chain)
export const DEMO_POOL_ID = '0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`
