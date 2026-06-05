/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        hedgehog: {
          green:  '#00D395',
          dark:   '#0D0F14',
          card:   '#151821',
          border: '#232634',
          muted:  '#6B7280',
        },
      },
      fontFamily: { sans: ['Inter', 'sans-serif'] },
    },
  },
  plugins: [],
}
