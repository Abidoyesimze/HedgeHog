export const HEDGE_VAULT_ABI = [
  { type: 'function', name: 'deposit', inputs: [{ name: 'usdcAmount', type: 'uint256' }], outputs: [{ name: 'shares', type: 'uint256' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'withdraw', inputs: [{ name: 'shares', type: 'uint256' }], outputs: [{ name: 'usdcAmount', type: 'uint256' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'balanceOf', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'totalSupply', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'totalCollateral', inputs: [], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'netDelta', inputs: [{ name: 'poolId', type: 'bytes32' }], outputs: [{ name: '', type: 'int256' }], stateMutability: 'view' },
  { type: 'function', name: 'deltaDriftBps', inputs: [{ name: 'poolId', type: 'bytes32' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'lastHedgedNotional', inputs: [{ name: '', type: 'bytes32' }], outputs: [{ name: '', type: 'int256' }], stateMutability: 'view' },
  { type: 'function', name: 'paused', inputs: [], outputs: [{ name: '', type: 'bool' }], stateMutability: 'view' },
  { type: 'event', name: 'HedgeExecuted', inputs: [{ name: 'poolId', type: 'bytes32', indexed: true }, { name: 'notionalDelta', type: 'int256', indexed: false }, { name: 'operator', type: 'address', indexed: false }], anonymous: false },
  { type: 'event', name: 'RebalanceRequested', inputs: [{ name: 'poolId', type: 'bytes32', indexed: true }, { name: 'currentDrift', type: 'int256', indexed: false }], anonymous: false },
] as const

export const ERC20_ABI = [
  { type: 'function', name: 'approve', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable' },
  { type: 'function', name: 'allowance', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'balanceOf', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'decimals', inputs: [], outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view' },
] as const
