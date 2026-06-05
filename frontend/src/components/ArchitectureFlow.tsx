'use client'

export function ArchitectureFlow() {
  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      <h2 className="font-semibold text-white mb-1">How It Works</h2>
      <p className="text-hedgehog-muted text-sm mb-6">Cross-chain delta-neutral hedging in 5 steps</p>

      <div className="flex flex-col md:flex-row items-stretch gap-2">
        <Step
          number="1"
          chain="Unichain"
          title="LP Deposits"
          detail="USDC into Hedgehog-wrapped Uniswap v4 pool"
          sponsor="Uniswap v4 Hook"
          color="bg-pink-500/10 border-pink-500/20 text-pink-400"
        />
        <Arrow />
        <Step
          number="2"
          chain="Unichain"
          title="Hook Fires"
          detail="afterAddLiquidity computes ETH exposure delta"
          sponsor="Uniswap v4"
          color="bg-pink-500/10 border-pink-500/20 text-pink-400"
        />
        <Arrow />
        <Step
          number="3"
          chain="Off-chain"
          title="AVS Computes"
          detail="EigenLayer operator sizes optimal hedge, signs instruction"
          sponsor="EigenLayer AVS"
          color="bg-blue-500/10 border-blue-500/20 text-blue-400"
        />
        <Arrow />
        <Step
          number="4"
          chain="Unichain → Arbitrum"
          title="Bridge"
          detail="Vault verifies sig, bridges USDC collateral via Across"
          sponsor="Across Protocol"
          color="bg-purple-500/10 border-purple-500/20 text-purple-400"
        />
        <Arrow />
        <Step
          number="5"
          chain="Arbitrum"
          title="Short Opens"
          detail="HedgehogArbitrum opens ETH short on GMX — IL neutralised"
          sponsor="GMX v2"
          color="bg-hedgehog-green/10 border-hedgehog-green/20 text-hedgehog-green"
        />
      </div>

      {/* Sponsor badges */}
      <div className="mt-6 pt-5 border-t border-hedgehog-border flex flex-wrap gap-2">
        {[
          { label: 'Uniswap v4 Hook', bg: 'bg-pink-500/10 border-pink-500/20 text-pink-400' },
          { label: 'EigenLayer AVS', bg: 'bg-blue-500/10 border-blue-500/20 text-blue-400' },
          { label: 'Across Bridge', bg: 'bg-purple-500/10 border-purple-500/20 text-purple-400' },
          { label: 'Circle USDC', bg: 'bg-yellow-500/10 border-yellow-500/20 text-yellow-400' },
          { label: 'Unichain Sepolia', bg: 'bg-hedgehog-green/10 border-hedgehog-green/20 text-hedgehog-green' },
        ].map(({ label, bg }) => (
          <span key={label} className={`text-xs px-3 py-1 rounded-full border font-medium ${bg}`}>
            {label}
          </span>
        ))}
      </div>
    </div>
  )
}

function Step({ number, chain, title, detail, sponsor, color }: {
  number: string; chain: string; title: string; detail: string; sponsor: string; color: string
}) {
  return (
    <div className="flex-1 bg-hedgehog-dark rounded-lg p-4 flex flex-col gap-2 min-w-0">
      <div className="flex items-center justify-between">
        <span className={`text-xs px-2 py-0.5 rounded-full border font-medium ${color}`}>{sponsor}</span>
        <span className="text-hedgehog-muted text-xs">{chain}</span>
      </div>
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="w-5 h-5 rounded-full bg-hedgehog-border text-hedgehog-muted text-xs flex items-center justify-center font-bold shrink-0">
            {number}
          </span>
          <p className="font-semibold text-white text-sm">{title}</p>
        </div>
        <p className="text-hedgehog-muted text-xs leading-relaxed">{detail}</p>
      </div>
    </div>
  )
}

function Arrow() {
  return (
    <div className="flex items-center justify-center text-hedgehog-border md:rotate-0 rotate-90 shrink-0 self-center">
      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </div>
  )
}
