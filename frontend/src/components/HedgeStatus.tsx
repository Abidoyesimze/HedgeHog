'use client'

import { useVaultStats } from '@/hooks/useHedgeVault'
import { formatUSDC, formatPct } from '@/lib/utils'

export function HedgeStatus() {
  const { totalCollateral, netDelta, driftBps, hedgedNotional, paused } = useVaultStats()

  const collateralRatio = totalCollateral && hedgedNotional && hedgedNotional !== 0n
    ? Number(totalCollateral) / Math.abs(Number(hedgedNotional)) * 100
    : null

  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      <div className="flex items-center justify-between mb-5">
        <h2 className="font-semibold text-white">Hedge Book</h2>
        <span className={`text-xs px-2 py-1 rounded-full font-medium ${
          paused
            ? 'bg-red-500/10 text-red-400 border border-red-500/20'
            : 'bg-hedgehog-green/10 text-hedgehog-green border border-hedgehog-green/20'
        }`}>
          {paused ? 'Paused' : 'Active'}
        </span>
      </div>

      <div className="space-y-4">
        <Row
          label="USDC Collateral"
          value={totalCollateral != null ? formatUSDC(totalCollateral) : '—'}
        />
        <Row
          label="Net Delta Exposure"
          value={netDelta != null ? `${Number(netDelta) / 1e18 >= 0 ? '+' : ''}${(Number(netDelta) / 1e18).toFixed(4)} ETH` : '—'}
          sub="positive = net long ETH"
        />
        <Row
          label="Current Hedge"
          value={hedgedNotional != null ? formatUSDC(BigInt(Math.abs(Number(hedgedNotional)))) : '—'}
          sub="short on GMX"
        />
        <Row
          label="Delta Drift"
          value={driftBps != null ? formatPct(driftBps) : '—'}
          accent={driftBps != null && driftBps > 200n}
          sub="rebalance fires at 2%"
        />
        {collateralRatio && (
          <Row
            label="Collateral Ratio"
            value={`${collateralRatio.toFixed(1)}%`}
            accent={collateralRatio < 110}
          />
        )}
      </div>
    </div>
  )
}

function Row({ label, value, sub, accent }: { label: string; value: string; sub?: string; accent?: boolean }) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-hedgehog-border/50 last:border-0">
      <div>
        <p className="text-sm text-hedgehog-muted">{label}</p>
        {sub && <p className="text-xs text-hedgehog-muted/60 mt-0.5">{sub}</p>}
      </div>
      <p className={`text-sm font-semibold tabular-nums ${accent ? 'text-red-400' : 'text-white'}`}>{value}</p>
    </div>
  )
}
