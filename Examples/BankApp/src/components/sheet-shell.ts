// SheetShell — common scaffold for a banking bottom-sheet.
//
// Layout:
//   ┌──────────────────────────────────────┐
//   │ ▔▔▔▔▔                                │  grabber (top, 36×4)
//   │                                      │
//   │  Title                           ✕   │  header row (title + dismiss)
//   │  Subtitle (optional)                 │
//   │                                      │
//   │  ───── scrollable content  ─────     │  scrollable body
//   │                                      │
//   │  ─────────────────────────────       │
//   │  [ ─── primary CTA ──── ]            │  sticky footer (safe-area bottom)
//   └──────────────────────────────────────┘
//
// Usage:
//   SheetShell({
//     title: 'Перевод',
//     subtitle: 'С Tinkoff Black ·· 4422',
//     onClose: dismissThisSheet,   // (optional — alert/swipe work anyway)
//     footer: PillButton({ label: 'Перевести', onTap: submit }),
//   }, ...bodyChildren)
//
// No external `backgroundColor`: iOS 26 itself shows Liquid Glass
// under the content; covering it with an opaque background breaks the morph
// to the .large detent.

import { colors, radius, space } from '../lib/colors'

interface SheetShellProps {
  title: string
  subtitle?: string | Thunk<string>
  /** If set — render the ✕ button on the right of the title. */
  onClose?: () => void
  /** Sticky footer — usually a PillButton with the primary action. */
  footer?: RenderNode | null
  /** Extra bottom-padding if the footer region is not needed. */
  contentPaddingBottom?: number
}

export function SheetShell(props: SheetShellProps, ...children: Child[]): RenderNode {
  return View(
    { flex: 1 },

    // Grabber: 36×4, crisp contrast against the material.
    View(
      { alignItems: 'center', paddingTop: 8, paddingBottom: space.sm },
      View({ width: 36, height: 5, borderRadius: 3, backgroundColor: '#FFFFFF35' }),
    ),

    // Header row
    View(
      {
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: space.md,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        paddingTop: space.xs,
        paddingBottom: space.md,
      },
      View(
        { flex: 1, gap: 2 },
        Text(
          { fontSize: 22, fontWeight: '800', color: colors.textPrimary, numberOfLines: 1 },
          props.title,
        ),
        props.subtitle != null
          ? (typeof props.subtitle === 'function'
              ? Text({ fontSize: 13, color: colors.textTertiary }, props.subtitle as Thunk<string>)
              : Text({ fontSize: 13, color: colors.textTertiary }, props.subtitle))
          : null,
      ),
      props.onClose
        ? closeButton(props.onClose)
        : null,
    ),

    // Scrollable body
    ScrollView(
      {
        flex: 1,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        paddingBottom: props.footer
          ? space.md
          : (props.contentPaddingBottom ?? Math.max(lumen.safeArea.bottom, space.lg)),
        gap: space.md,
      },
      ...children,
    ),

    // Sticky footer
    props.footer
      ? View(
          {
            paddingLeft: space.lg,
            paddingRight: space.lg,
            paddingTop: space.md,
            paddingBottom: Math.max(lumen.safeArea.bottom, space.md),
            // Hairline on top, separates footer from the scroll area.
            borderColor: colors.divider,
            borderWidth: 0,
          },
          // hairline
          View({ height: 1, backgroundColor: colors.divider, borderRadius: 1 }),
          View({ height: space.md }),
          props.footer,
        )
      : null,
  )
}

function closeButton(onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap: () => { lumen.haptics('soft'); onTap() },
      width: 36, height: 36, borderRadius: 18,
      backgroundColor: colors.surfaceElevated,
      alignItems: 'center', justifyContent: 'center',
    },
    Text({ fontSize: 16, fontWeight: '700', color: colors.textSecondary }, '✕'),
  )
}
