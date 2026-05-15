// Profile. Account info + a demo mock-deposit button (for testing
// balance reactivity + the scene).

import { Header } from '../components/header'
import { GlassCard } from '../components/glass-card'
import { colors, radius, space } from '../lib/colors'
import { account } from '../state/account'
import { receiveDeposit } from '../services/bank-api'
import { TAB_BAR_HEIGHT } from '../state/ui'

export function profilePage() {
  return {
    render: renderProfile,
  }
}

function renderProfile(): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Profile' }),

    ScrollView(
      {
        flex: 1,
        paddingTop: space.md,
        paddingBottom: TAB_BAR_HEIGHT + Math.max(lumen.safeArea.bottom, space.lg) + space.lg,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.lg,
      },

      // Avatar block
      View(
        { alignItems: 'center', gap: space.md, paddingTop: space.lg, paddingBottom: space.md },
        View(
          {
            width: 88, height: 88, borderRadius: 44, // round avatar — half of size
            backgroundColor: colors.accent,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 36, fontWeight: '800', color: colors.textPrimary }, () => initials(account.value.holderName)),
        ),
        Text({ fontSize: 20, fontWeight: '700', color: colors.textPrimary }, () => account.value.holderName),
      ),

      // Account info
      GlassCard(
        {},
        Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'ACCOUNT'),
        infoRow('IBAN', () => account.value.iban),
        infoRow('Card', () => '•••• ' + account.value.cardLast4),
      ),

      // Settings
      GlassCard(
        {},
        Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'SETTINGS'),
        settingsRow('Face ID for transfers', () => lumen.biometrics.available() !== 'none' ? 'Available' : 'Unavailable'),
        settingsRow('Notifications', () => 'Not configured'),
      ),

      // Dev tools — for testing reactivity and feeding money into the demo account.
      GlassCard(
        {},
        Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'DEV'),
        Pressable(
          {
            onTap: async () => {
              lumen.haptics('medium')
              await receiveDeposit(500_00, 'Mock deposit')
            },
            paddingTop: space.md, paddingBottom: space.md,
            paddingLeft: space.md, paddingRight: space.md,
            borderRadius: radius.control,
            backgroundColor: colors.surfaceElevated,
          },
          Text({ fontSize: 14, color: colors.accentHi, fontWeight: '600' }, '+ Add $500 (mock)'),
        ),
      ),
    ),
  )
}

function infoRow(label: string, value: Thunk<string>): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.md, alignItems: 'center' },
    Text({ flex: 1, fontSize: 13, color: colors.textTertiary }, label),
    Text({ fontSize: 13, color: colors.textPrimary, fontWeight: '500' }, value),
  )
}

function settingsRow(label: string, value: Thunk<string>): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.md, alignItems: 'center', paddingTop: space.xs, paddingBottom: space.xs },
    Text({ flex: 1, fontSize: 14, color: colors.textPrimary }, label),
    Text({ fontSize: 13, color: colors.textSecondary }, value),
  )
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0]!.charAt(0).toUpperCase()
  return (parts[0]!.charAt(0) + parts[parts.length - 1]!.charAt(0)).toUpperCase()
}
