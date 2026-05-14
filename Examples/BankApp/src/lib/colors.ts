// Дизайн-токены. Один источник правды для палитры — страницы и компоненты
// не пишут хексы напрямую. Имена нейтральные (bg / surface / accent), чтобы
// легко перекраситься, не правя 30 файлов.

export const colors = {
  bg: '#0B0B0F',
  surface: '#16161D',
  surfaceElevated: '#1F1F29',
  border: '#262633',

  textPrimary: '#FFFFFF',
  textSecondary: '#A8A8B8',
  textTertiary: '#6C6C7A',

  accent: '#7B6CFF',
  accentHi: '#9A8CFF',

  positive: '#3CD18E',
  negative: '#FF6B6B',
} as const

export const radius = {
  card: 18,
  pill: 999,
  control: 14,
} as const

export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
} as const
