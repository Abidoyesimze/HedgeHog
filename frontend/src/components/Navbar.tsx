'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'

export function Navbar() {
  return (
    <header className="border-b border-hedgehog-border bg-hedgehog-dark/80 backdrop-blur-sm sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-2xl">🦔</span>
          <span className="font-bold text-lg tracking-tight">Hedgehog</span>
          <span className="text-xs bg-hedgehog-green/10 text-hedgehog-green border border-hedgehog-green/20 px-2 py-0.5 rounded-full font-medium">
            Testnet
          </span>
        </div>
        <ConnectButton chainStatus="icon" showBalance={false} />
      </div>
    </header>
  )
}
