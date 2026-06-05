'use client'

import { useEffect, useState } from 'react'
import { createPublicClient, http, parseAbiItem } from 'viem'
import { unichainSepolia } from '@/lib/chains'
import { UNICHAIN_ADDRESSES } from '@/lib/addresses'
import { formatUSDC } from '@/lib/utils'

interface HedgeEvent {
  type: 'HedgeExecuted' | 'RebalanceRequested'
  poolId: string
  notional?: bigint
  drift?: bigint
  txHash: string
  blockNumber: bigint
}

const client = createPublicClient({
  chain: unichainSepolia,
  transport: http('https://sepolia.unichain.org'),
})

const VAULT = UNICHAIN_ADDRESSES.hedgeVault as `0x${string}`

export function ActivityFeed() {
  const [events, setEvents] = useState<HedgeEvent[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function fetchEvents() {
      try {
        const [hedgeExec, rebalance] = await Promise.all([
          client.getLogs({
            address: VAULT,
            event: parseAbiItem('event HedgeExecuted(bytes32 indexed poolId, int256 notionalDelta, address operator)'),
            fromBlock: 'earliest',
          }),
          client.getLogs({
            address: VAULT,
            event: parseAbiItem('event RebalanceRequested(bytes32 indexed poolId, int256 currentDrift)'),
            fromBlock: 'earliest',
          }),
        ])

        const all: HedgeEvent[] = [
          ...hedgeExec.map((e) => ({
            type: 'HedgeExecuted' as const,
            poolId: (e.args.poolId as string).slice(0, 10) + '...',
            notional: e.args.notionalDelta as bigint,
            txHash: e.transactionHash ?? '',
            blockNumber: e.blockNumber ?? 0n,
          })),
          ...rebalance.map((e) => ({
            type: 'RebalanceRequested' as const,
            poolId: (e.args.poolId as string).slice(0, 10) + '...',
            drift: e.args.currentDrift as bigint,
            txHash: e.transactionHash ?? '',
            blockNumber: e.blockNumber ?? 0n,
          })),
        ].sort((a, b) => Number(b.blockNumber - a.blockNumber)).slice(0, 8)

        setEvents(all)
      } catch {
        // silently fail — testnet may have no logs yet
      } finally {
        setLoading(false)
      }
    }

    fetchEvents()
    const interval = setInterval(fetchEvents, 30_000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-6">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h2 className="font-semibold text-white">Live Activity</h2>
          <p className="text-hedgehog-muted text-sm mt-0.5">On-chain hedge events from Unichain Sepolia</p>
        </div>
        <span className="flex items-center gap-1.5 text-xs text-hedgehog-green">
          <span className="w-1.5 h-1.5 rounded-full bg-hedgehog-green animate-pulse" />
          Live
        </span>
      </div>

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-12 bg-hedgehog-dark rounded-lg animate-pulse" />
          ))}
        </div>
      ) : events.length === 0 ? (
        <div className="text-center py-8">
          <p className="text-hedgehog-muted text-sm">No hedge events yet</p>
          <p className="text-hedgehog-muted/60 text-xs mt-1">Events will appear here after the first deposit triggers a hedge</p>
        </div>
      ) : (
        <div className="space-y-2">
          {events.map((e, i) => (
            <div key={i} className="flex items-center justify-between p-3 bg-hedgehog-dark rounded-lg">
              <div className="flex items-center gap-3">
                <span className={`w-2 h-2 rounded-full shrink-0 ${
                  e.type === 'HedgeExecuted' ? 'bg-hedgehog-green' : 'bg-yellow-400'
                }`} />
                <div>
                  <p className="text-sm text-white font-medium">
                    {e.type === 'HedgeExecuted' ? 'Hedge Executed' : 'Rebalance Triggered'}
                  </p>
                  <p className="text-xs text-hedgehog-muted">
                    {e.type === 'HedgeExecuted' && e.notional != null
                      ? `Notional: ${formatUSDC(e.notional < 0n ? -e.notional : e.notional)}`
                      : e.drift != null
                        ? `Drift: ${(Number(e.drift) / 100).toFixed(2)}%`
                        : ''}
                  </p>
                </div>
              </div>
              {e.txHash && (
                <a
                  href={`https://unichain-sepolia.blockscout.com/tx/${e.txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-hedgehog-muted hover:text-hedgehog-green transition-colors"
                >
                  {e.txHash.slice(0, 8)}... ↗
                </a>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
