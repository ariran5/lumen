// Avatar — round tile with initials on a yellow background (T-Bank style).
// Used in the home header and on the profile page.

import { colors, radius } from '../lib/colors'

interface AvatarProps {
  /** Full name — initials are derived. */
  name: string
  size?: number
  /** Force background (default — accent). */
  bg?: Color
  /** Force text color. */
  color?: Color
  onTap?: () => void
}

function initials(fullName: string): string {
  const parts = fullName.trim().split(/\s+/).slice(0, 2)
  return parts.map(p => p[0] ?? '').join('').toUpperCase()
}

export function Avatar(p: AvatarProps): RenderNode {
  const size = p.size ?? 40
  const bg = p.bg ?? colors.accent
  const color = p.color ?? colors.textOnAccent
  const inner = View(
    {
      width: size,
      height: size,
      borderRadius: size / 2,
      backgroundColor: bg,
      alignItems: 'center',
      justifyContent: 'center',
    },
    Text(
      { fontSize: Math.round(size * 0.4), fontWeight: '700', color },
      initials(p.name),
    ),
  )
  if (!p.onTap) return inner
  return Pressable(
    {
      onTap: () => { lumen.haptics('soft'); p.onTap!() },
      width: size, height: size,
      borderRadius: size / 2,
    },
    inner,
  )
}
