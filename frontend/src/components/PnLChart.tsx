'use client'

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from 'recharts'
import { useMemo } from 'react'

interface Props {
  ethPrice: number  // current simulated ETH price
}

function buildChartData(currentPrice: number) {
  const startPrice = 3000
  const points = 30
  const data = []

  for (let i = 0; i <= points; i++) {
    const price = startPrice + ((currentPrice - startPrice) * i) / points
    const priceRatio = price / startPrice

    // Vanilla LP P&L: Uniswap x*y=k formula, IL = 2*sqrt(r)/(1+r) - 1
    const r = priceRatio
    const ilFactor = (2 * Math.sqrt(r)) / (1 + r) - 1
    const vanillaFees = (i / points) * 150  // ~5% APR fees over the period
    const vanillaPnl = 10000 * ilFactor + vanillaFees

    // Hedgehog LP P&L: IL cancelled by short, only fees remain
    const hedgehogFees = (i / points) * 150
    // Small hedge cost (funding rate + bridge fees ~0.3% of notional)
    const hedgeCost = (i / points) * 10000 * 0.003
    const hedgehogPnl = hedgehogFees - hedgeCost

    data.push({
      price: `$${Math.round(price)}`,
      vanilla: Math.round(vanillaPnl),
      hedgehog: Math.round(hedgehogPnl),
    })
  }
  return data
}

const CustomTooltip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-lg p-3 text-sm shadow-xl">
      <p className="text-hedgehog-muted mb-2">ETH price: {label}</p>
      {payload.map((p: any) => (
        <p key={p.name} style={{ color: p.color }} className="font-medium">
          {p.name}: {p.value >= 0 ? '+' : ''}{p.value.toLocaleString()} USDC
        </p>
      ))}
    </div>
  )
}

export function PnLChart({ ethPrice }: Props) {
  const data = useMemo(() => buildChartData(ethPrice), [ethPrice])

  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="font-semibold text-white">P&amp;L Comparison</h2>
          <p className="text-hedgehog-muted text-sm mt-0.5">$10,000 deposit — Vanilla LP vs Hedgehog LP</p>
        </div>
        <div className="flex items-center gap-4 text-xs">
          <span className="flex items-center gap-1.5">
            <span className="w-3 h-0.5 bg-red-400 inline-block rounded" />
            <span className="text-hedgehog-muted">Vanilla LP</span>
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-3 h-0.5 bg-hedgehog-green inline-block rounded" />
            <span className="text-hedgehog-muted">Hedgehog LP</span>
          </span>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={260}>
        <LineChart data={data} margin={{ top: 4, right: 4, left: 0, bottom: 4 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#232634" />
          <XAxis dataKey="price" tick={{ fill: '#6B7280', fontSize: 11 }} interval={5} />
          <YAxis tick={{ fill: '#6B7280', fontSize: 11 }} tickFormatter={(v) => `$${v}`} />
          <Tooltip content={<CustomTooltip />} />
          <Line
            type="monotone" dataKey="vanilla" stroke="#F87171"
            strokeWidth={2} dot={false} name="Vanilla LP"
          />
          <Line
            type="monotone" dataKey="hedgehog" stroke="#00D395"
            strokeWidth={2} dot={false} name="Hedgehog LP"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
