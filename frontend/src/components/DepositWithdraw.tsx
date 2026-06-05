'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { formatUnits } from 'viem'
import { useDeposit, useWithdraw, useUserPosition, useVaultStats } from '@/hooks/useHedgeVault'
import { formatUSDC, cn } from '@/lib/utils'

export function DepositWithdraw() {
  const { isConnected } = useAccount()
  const [tab, setTab] = useState<'deposit' | 'withdraw'>('deposit')
  const [amount, setAmount] = useState('')
  const [isRefreshing, setIsRefreshing] = useState(false)

  const { shares, usdcBalance, allowance, refetchAllowance, refetchAll: refetchPosition } = useUserPosition()
  const { refetchAll: refetchVault } = useVaultStats()
  const { approve, deposit, isApprovePending, isApproveSuccess, isDepositPending, isDepositSuccess } = useDeposit()
  const { withdraw, isPending: isWithdrawPending, isSuccess: isWithdrawSuccess } = useWithdraw()

  // Refetch allowance immediately after approve confirms
  useEffect(() => {
    if (isApproveSuccess) refetchAllowance()
  }, [isApproveSuccess])

  // Refetch all balances immediately after deposit confirms
  useEffect(() => {
    if (isDepositSuccess) {
      refetchPosition()
      refetchVault()
      setAmount('')
    }
  }, [isDepositSuccess])

  // Refetch all balances immediately after withdraw confirms
  useEffect(() => {
    if (isWithdrawSuccess) {
      refetchPosition()
      refetchVault()
      setAmount('')
    }
  }, [isWithdrawSuccess])

  async function handleManualRefresh() {
    setIsRefreshing(true)
    await Promise.all([refetchPosition(), refetchVault()])
    setTimeout(() => setIsRefreshing(false), 600)
  }

  const parsedAmount = amount ? parseFloat(amount) * 1e6 : 0
  const needsApproval = tab === 'deposit' && BigInt(Math.floor(parsedAmount)) > allowance
  const isLoading = isApprovePending || isDepositPending || isWithdrawPending

  if (!isConnected) {
    return (
      <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6 text-center">
        <p className="text-2xl mb-2">🦔</p>
        <p className="text-white font-medium">Connect your wallet</p>
        <p className="text-hedgehog-muted text-sm mt-1">to deposit and earn delta-neutral yield</p>
      </div>
    )
  }

  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      {/* Header with manual refresh */}
      <div className="flex items-center justify-between mb-5">
        <div className="flex rounded-lg bg-hedgehog-dark p-1 flex-1 mr-3">
          {(['deposit', 'withdraw'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                'flex-1 py-2 text-sm font-medium rounded-md transition-all capitalize',
                tab === t ? 'bg-hedgehog-card text-white shadow' : 'text-hedgehog-muted hover:text-white'
              )}
            >
              {t}
            </button>
          ))}
        </div>
        <button
          onClick={handleManualRefresh}
          title="Refresh balances"
          className="p-2 rounded-lg border border-hedgehog-border text-hedgehog-muted hover:text-white hover:border-hedgehog-green transition-all"
        >
          <svg
            className={cn('w-4 h-4', isRefreshing && 'animate-spin')}
            fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>

      {/* Amount input */}
      <div className="mb-4">
        <div className="flex justify-between text-sm mb-2">
          <span className="text-hedgehog-muted">Amount (USDC)</span>
          <span className="text-hedgehog-muted">
            {tab === 'deposit'
              ? <>Balance: <span className="text-white font-medium">{formatUSDC(usdcBalance)}</span></>
              : <>Shares: <span className="text-white font-medium">{Number(formatUnits(shares, 6)).toLocaleString()}</span></>}
          </span>
        </div>
        <div className="relative">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="w-full bg-hedgehog-dark border border-hedgehog-border rounded-lg px-4 py-3 text-white text-lg font-medium outline-none focus:border-hedgehog-green transition-colors"
          />
          <button
            onClick={() => setAmount(tab === 'deposit' ? formatUnits(usdcBalance, 6) : formatUnits(shares, 6))}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-hedgehog-green font-medium hover:opacity-80"
          >
            MAX
          </button>
        </div>
      </div>

      {/* Deposit info */}
      {tab === 'deposit' && (
        <div className="bg-hedgehog-dark rounded-lg p-3 mb-4 text-xs text-hedgehog-muted space-y-1">
          <p className="flex justify-between"><span>Estimated APY</span><span className="text-hedgehog-green font-medium">~8–12%</span></p>
          <p className="flex justify-between"><span>Hedge cost (funding)</span><span>~0.3%/yr</span></p>
          <p className="flex justify-between"><span>IL protection</span><span className="text-hedgehog-green font-medium">100%</span></p>
        </div>
      )}

      {/* Action button */}
      <button
        onClick={() => {
          if (!amount || parseFloat(amount) <= 0) return
          if (tab === 'deposit') {
            if (needsApproval) { approve(amount); return }
            deposit(amount)
          } else {
            withdraw(BigInt(Math.floor(parsedAmount)))
          }
        }}
        disabled={isLoading || !amount || parseFloat(amount) <= 0}
        className={cn(
          'w-full py-3 rounded-lg font-semibold text-sm transition-all',
          isLoading || !amount || parseFloat(amount) <= 0
            ? 'bg-hedgehog-border text-hedgehog-muted cursor-not-allowed'
            : 'bg-hedgehog-green text-hedgehog-dark hover:opacity-90 active:scale-[0.98]'
        )}
      >
        {isLoading
          ? <span className="flex items-center justify-center gap-2">
              <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
              </svg>
              Confirming...
            </span>
          : needsApproval ? 'Approve USDC'
          : tab === 'deposit' ? 'Deposit'
          : 'Withdraw'}
      </button>

      {/* Success message */}
      {(isDepositSuccess || isWithdrawSuccess) && (
        <p className="text-center text-hedgehog-green text-sm mt-3 flex items-center justify-center gap-1.5">
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
          Transaction confirmed — balances updated
        </p>
      )}
    </div>
  )
}
