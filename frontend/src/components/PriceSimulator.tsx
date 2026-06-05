'use client'

interface Props {
  ethPrice: number
  onChange: (price: number) => void
}

export function PriceSimulator({ ethPrice, onChange }: Props) {
  const change = ((ethPrice - 3000) / 3000 * 100).toFixed(1)
  const isUp = ethPrice >= 3000

  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="font-semibold text-white">Price Simulator</h2>
          <p className="text-hedgehog-muted text-sm mt-0.5">Drag to simulate ETH price move</p>
        </div>
        <div className="text-right">
          <p className="text-2xl font-bold text-white">${ethPrice.toLocaleString()}</p>
          <p className={`text-sm font-medium ${isUp ? 'text-hedgehog-green' : 'text-red-400'}`}>
            {isUp ? '+' : ''}{change}% from $3,000
          </p>
        </div>
      </div>

      <input
        type="range"
        min={1000}
        max={6000}
        step={50}
        value={ethPrice}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full accent-[#00D395] cursor-pointer"
      />

      <div className="flex justify-between text-xs text-hedgehog-muted mt-2">
        <span>$1,000 (−67%)</span>
        <span className="text-hedgehog-muted">Start: $3,000</span>
        <span>$6,000 (+100%)</span>
      </div>

      <div className="mt-4 p-3 rounded-lg bg-hedgehog-dark border border-hedgehog-border">
        <p className="text-xs text-hedgehog-muted">
          {Math.abs(Number(change)) > 5
            ? `⚡ At this price, a Vanilla LP would have lost ${Math.abs(Math.round(10000 * ((2 * Math.sqrt(ethPrice / 3000)) / (1 + ethPrice / 3000) - 1))).toLocaleString()} USDC to IL. Hedgehog LPs keep their principal.`
            : '📊 Move the slider to see IL impact on a $10,000 position.'}
        </p>
      </div>
    </div>
  )
}
