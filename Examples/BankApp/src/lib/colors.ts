// Design tokens for the T-Bank style. Dark background, bright-yellow accent,
// black text over yellow. `accentHi` is kept as an alias for yellow so
// existing spots ("See all →" links etc.) keep working.

export const colors = {
  // Background and surfaces
  bg: '#0E0E10',
  surface: '#18181C',
  surfaceElevated: '#222228',
  surfaceMuted: '#14141A',
  border: '#26262E',
  divider: '#1F1F26',

  // Text
  textPrimary: '#FFFFFF',
  textSecondary: '#A6A6B0',
  textTertiary: '#6D6D78',
  textOnAccent: '#0E0E10',

  // Brand
  accent: '#FFDD2D',
  accentHi: '#FFE65A',
  accentDim: '#E0C228',
  accentSoft: '#3D3618',

  // Cards (background tint by account type)
  cardBlack: '#1A1A1F',
  cardPremium: '#2A2018',
  cardSavings: '#1B2A22',
  cardInvest: '#1D1B2C',
  cardCredit: '#2A1B22',

  // Icon tiles in the services grid — subtle tints by category
  tilePay: '#2A2410',
  tileTransfer: '#1A222E',
  tileQR: '#1F1A2B',
  tileGov: '#1A2A23',
  tileMobile: '#2C1F1A',
  tileTravel: '#2B1F2A',

  // Signals
  positive: '#4ADE80',
  negative: '#FF6160',
  warning: '#FFB347',
} as const

export const radius = {
  card: 18,
  control: 14,
  // ⚠️ Lumen / iOS 26: cornerRadius > min(width, height)/2 isn't clamped
  // and makes the CALayer an empty mask — the node becomes invisible. So
  // `pill` is half of a typical pill-button height (44–56pt) = 28.
  // For perfectly round elements (avatar 88×88, icon 40×40) write
  // borderRadius: size/2 explicitly.
  pill: 28,
  storyAvatar: 36,
} as const

export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 28,
} as const
