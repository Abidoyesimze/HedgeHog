import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatUSDC(raw: bigint, decimals = 6): string {
  const val = Number(raw) / 10 ** decimals
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 }).format(val)
}

export function formatPct(bps: bigint): string {
  return (Number(bps) / 100).toFixed(2) + '%'
}

export function shortenAddress(addr: string): string {
  return addr.slice(0, 6) + '...' + addr.slice(-4)
}
