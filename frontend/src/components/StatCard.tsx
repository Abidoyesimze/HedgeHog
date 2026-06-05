import { cn } from '@/lib/utils'

interface StatCardProps {
  label: string
  value: string
  sub?: string
  accent?: boolean
}

export function StatCard({ label, value, sub, accent }: StatCardProps) {
  return (
    <div className="bg-hedgehog-card border border-hedgehog-border rounded-xl p-5">
      <p className="text-hedgehog-muted text-sm mb-1">{label}</p>
      <p className={cn('text-2xl font-bold', accent ? 'text-hedgehog-green' : 'text-white')}>{value}</p>
      {sub && <p className="text-hedgehog-muted text-xs mt-1">{sub}</p>}
    </div>
  )
}
