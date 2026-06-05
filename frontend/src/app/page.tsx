'use client'

import { useState } from 'react'
import { Navbar } from '@/components/Navbar'
import { StatCard } from '@/components/StatCard'
import { PnLChart } from '@/components/PnLChart'
import { PriceSimulator } from '@/components/PriceSimulator'
import { HedgeStatus } from '@/components/HedgeStatus'
import { DepositWithdraw } from '@/components/DepositWithdraw'
import { ArchitectureFlow } from '@/components/ArchitectureFlow'
import { ActivityFeed } from '@/components/ActivityFeed'
import { useVaultStats, useUserPosition } from '@/hooks/useHedgeVault'
import { formatUSDC } from '@/lib/utils'
import { formatUnits } from 'viem'

export default function DashboardPage() {
  const [ethPrice, setEthPrice] = useState(3000)
  const { totalCollateral, totalSupply } = useVaultStats()
  const { shares } = useUserPosition()

  const r = ethPrice / 3000
  const ilPct = ((2 * Math.sqrt(r)) / (1 + r) - 1) * 100

  return (
    <div className="min-h-screen bg-hedgehog-dark">
      <Navbar />

      <main className="max-w-7xl mx-auto px-6 py-8 space-y-8">

        {/* Hero */}
        <div className="rounded-2xl border border-hedgehog-green/20 bg-gradient-to-r from-hedgehog-green/5 to-transparent p-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-white">Delta-Neutral Liquidity</h1>
            <p className="text-hedgehog-muted mt-1 max-w-lg">
              Earn Uniswap v4 swap fees with zero directional ETH exposure.
              Your LP position is automatically hedged on GMX via EigenLayer AVS.
            </p>
          </div>
          <div className="hidden md:flex items-center gap-3 text-xs">
            <Pill label="Uniswap v4 Hook" />
            <Pill label="EigenLayer AVS" />
            <Pill label="Across Bridge" />
          </div>
        </div>

        {/* Top stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard
            label="Total Value Locked"
            value={totalCollateral != null ? formatUSDC(totalCollateral) : '$—'}
            accent
          />
          <StatCard
            label="LP Shares Issued"
            value={totalSupply != null ? Number(formatUnits(totalSupply, 6)).toLocaleString() : '—'}
            sub="HHDG tokens"
          />
          <StatCard
            label="Your Position"
            value={shares > 0n ? formatUSDC(shares) : '$0.00'}
            sub={shares > 0n ? 'earning yield' : 'not deposited'}
          />
          <StatCard
            label="Vanilla LP IL Now"
            value={`${ilPct.toFixed(2)}%`}
            sub="at simulated ETH price"
            accent={Math.abs(ilPct) > 2}
          />
        </div>

        {/* Architecture flow */}
        <ArchitectureFlow />

        {/* Price simulator + Chart */}
        <div className="space-y-4">
          <PriceSimulator ethPrice={ethPrice} onChange={setEthPrice} />
          <PnLChart ethPrice={ethPrice} />
        </div>

        {/* Hedge book + Deposit */}
        <div className="grid md:grid-cols-2 gap-6">
          <HedgeStatus />
          <DepositWithdraw />
        </div>

        {/* Live activity feed */}
        <ActivityFeed />

        {/* Footer */}
        <footer className="border-t border-hedgehog-border pt-6 pb-4 flex items-center justify-between text-xs text-hedgehog-muted">
          <span>Hedgehog Protocol — UHI9 Hookathon 2026</span>
          <div className="flex gap-4">
            <a href="https://sourcify.dev/#/lookup/1301/0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C" target="_blank" className="hover:text-white transition-colors">Vault ↗</a>
            <a href="https://sourcify.dev/#/lookup/1301/0x7F11fcE1603c806D14c8F7D35E7B0e4B785F02f9" target="_blank" className="hover:text-white transition-colors">Hook ↗</a>
            <a href="https://sourcify.dev/#/lookup/421614/0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C" target="_blank" className="hover:text-white transition-colors">Arbitrum ↗</a>
          </div>
        </footer>
      </main>
    </div>
  )
}

function Pill({ label }: { label: string }) {
  return (
    <span className="bg-hedgehog-card border border-hedgehog-border px-3 py-1.5 rounded-full text-hedgehog-muted">
      {label}
    </span>
  )
}
