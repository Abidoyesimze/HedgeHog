'use client'

import { useReadContract, useWriteContract, useAccount, useWaitForTransactionReceipt } from 'wagmi'
import { parseUnits } from 'viem'
import { HEDGE_VAULT_ABI, ERC20_ABI } from '@/lib/abis'
import { UNICHAIN_ADDRESSES, DEMO_POOL_ID } from '@/lib/addresses'
import { unichainSepolia } from '@/lib/chains'

const VAULT = UNICHAIN_ADDRESSES.hedgeVault as `0x${string}`
const USDC  = UNICHAIN_ADDRESSES.usdc as `0x${string}`
const POLL_INTERVAL = 15_000 // 15s live refresh

export function useVaultStats() {
  const { data: totalCollateral, refetch: refetchCollateral } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'totalCollateral',
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })
  const { data: totalSupply, refetch: refetchSupply } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'totalSupply',
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })
  const { data: netDelta } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'netDelta',
    args: [DEMO_POOL_ID],
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })
  const { data: driftBps } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'deltaDriftBps',
    args: [DEMO_POOL_ID],
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })
  const { data: hedgedNotional } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'lastHedgedNotional',
    args: [DEMO_POOL_ID],
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })
  const { data: paused } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'paused',
    chainId: unichainSepolia.id,
    query: { refetchInterval: POLL_INTERVAL },
  })

  function refetchAll() {
    refetchCollateral()
    refetchSupply()
  }

  return { totalCollateral, totalSupply, netDelta, driftBps, hedgedNotional, paused, refetchAll }
}

export function useUserPosition() {
  const { address } = useAccount()
  const zero = '0x0000000000000000000000000000000000000000' as `0x${string}`

  const { data: shares, refetch: refetchShares } = useReadContract({
    address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'balanceOf',
    args: [address ?? zero],
    chainId: unichainSepolia.id,
    query: { enabled: !!address, refetchInterval: POLL_INTERVAL },
  })
  const { data: usdcBalance, refetch: refetchUsdcBalance } = useReadContract({
    address: USDC, abi: ERC20_ABI, functionName: 'balanceOf',
    args: [address ?? zero],
    chainId: unichainSepolia.id,
    query: { enabled: !!address, refetchInterval: POLL_INTERVAL },
  })
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: USDC, abi: ERC20_ABI, functionName: 'allowance',
    args: [address ?? zero, VAULT],
    chainId: unichainSepolia.id,
    query: { enabled: !!address, refetchInterval: POLL_INTERVAL },
  })

  function refetchAll() {
    refetchShares()
    refetchUsdcBalance()
    refetchAllowance()
  }

  return {
    shares: shares ?? 0n,
    usdcBalance: usdcBalance ?? 0n,
    allowance: allowance ?? 0n,
    refetchAllowance,
    refetchAll,
  }
}

export function useDeposit() {
  const { writeContract, data: approveTxHash, isPending: isApprovePending } = useWriteContract()
  const { writeContract: writeDeposit, data: depositTxHash, isPending: isDepositPending } = useWriteContract()

  const { isLoading: isApproveLoading, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash })
  const { isLoading: isDepositLoading, isSuccess: isDepositSuccess } = useWaitForTransactionReceipt({ hash: depositTxHash })

  function approve(amount: string) {
    writeContract({ address: USDC, abi: ERC20_ABI, functionName: 'approve', args: [VAULT, parseUnits(amount, 6)] })
  }

  function deposit(amount: string) {
    writeDeposit({ address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'deposit', args: [parseUnits(amount, 6)] })
  }

  return {
    approve, deposit,
    isApprovePending: isApprovePending || isApproveLoading,
    isApproveSuccess,
    isDepositPending: isDepositPending || isDepositLoading,
    isDepositSuccess,
  }
}

export function useWithdraw() {
  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  function withdraw(shares: bigint) {
    writeContract({ address: VAULT, abi: HEDGE_VAULT_ABI, functionName: 'withdraw', args: [shares] })
  }

  return { withdraw, isPending: isPending || isLoading, isSuccess }
}
