// Promo banner — yellow tile with title + button. T-Bank uses it
// for cashback, Tinkoff Pro, partners. Tap is an alert stub;
// in production it would push to a promo page.

import { colors, radius, space } from '../lib/colors'

interface PromoBannerProps {
  title: string
  subtitle: string
  cta?: string
  icon?: string
  /** Background color. Default — accent (yellow). */
  bg?: Color
  /** Text color. Default — black (for yellow background). */
  fg?: Color
  onTap?: () => void
}

export function PromoBanner(p: PromoBannerProps): RenderNode {
  const bg = p.bg ?? colors.accent
  const fg = p.fg ?? colors.textOnAccent
  const fgSub = p.fg ?? '#0E0E1099'

  return Pressable(
    {
      onTap: () => {
        lumen.haptics('soft')
        if (p.onTap) p.onTap()
        else lumen.alert({ title: p.title, message: p.subtitle })
      },
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      padding: space.lg,
      borderRadius: radius.card,
      backgroundColor: bg,
    },
    View(
      { flex: 1, gap: space.xs },
      Text({ fontSize: 16, fontWeight: '800', color: fg, numberOfLines: 2, lineHeight: 19 }, p.title),
      Text({ fontSize: 12, fontWeight: '500', color: fgSub, numberOfLines: 3, lineHeight: 16 }, p.subtitle),
      p.cta
        ? Text(
            {
              fontSize: 13,
              fontWeight: '700',
              color: fg,
              paddingTop: space.xs,
            },
            p.cta + ' →',
          )
        : null,
    ),
    p.icon
      ? View(
          {
            width: 56, height: 56, borderRadius: 28,
            backgroundColor: '#FFFFFF22',
            alignItems: 'center',
            justifyContent: 'center',
            
          },
          Text({ fontSize: 30 }, p.icon),
        )
      : null,
  )
}
