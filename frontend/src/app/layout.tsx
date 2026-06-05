import type { Metadata } from 'next'
import { Providers } from './providers'
import './globals.css'

export const metadata: Metadata = {
  title: 'Hedgehog — Delta-Neutral LP',
  description: 'Earn swap fees without impermanent loss. Powered by Uniswap v4 hooks and EigenLayer AVS.',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}
