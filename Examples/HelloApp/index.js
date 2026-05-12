// ─────────────────────────────────────────────────────────────────
// Hello Lumen — example fast-app
//
// This file is fetched by Lumen at startup, evaluated in JSContext,
// and renders the UI by calling `lumen.render(...)`.
// After 800ms it presents a native iOS bottom sheet whose content
// is *also* a Lumen view-tree.
// ─────────────────────────────────────────────────────────────────

console.log('hello lumen — entry script running')

function row(icon, title, subtitle, accent) {
  return {
    type: 'view',
    style: {
      flexDirection: 'row',
      padding: 14,
      gap: 14,
      height: 68,
      backgroundColor: '#1C1C22',
      borderRadius: 14,
    },
    children: [
      {
        type: 'view',
        style: { width: 40, height: 40, borderRadius: 20, backgroundColor: accent },
      },
      {
        type: 'view',
        style: { flex: 1, gap: 4, height: 40 },
        children: [
          {
            type: 'text',
            text: title,
            style: { fontSize: 16, fontWeight: '600', color: '#FFFFFF', height: 22 },
          },
          {
            type: 'text',
            text: subtitle,
            style: { fontSize: 12, color: '#9CA3AF', height: 16 },
          },
        ],
      },
    ],
  }
}

const screen = {
  type: 'view',
  style: {
    flex: 1,
    padding: 20,
    gap: 12,
    backgroundColor: '#0F0F12',
  },
  children: [
    {
      type: 'text',
      text: 'Hello Lumen',
      style: { fontSize: 32, fontWeight: '700', color: '#FFFFFF', height: 40 },
    },
    {
      type: 'text',
      text: 'This screen is rendered by a JS bundle served from your laptop — every node you see is a CALayer, no DOM or WebView involved.',
      style: { fontSize: 13, color: '#9CA3AF', numberOfLines: 3, lineHeight: 18, height: 56 },
    },
    row('★', 'Native primitives', 'CALayer per node, GPU-composited', '#6366F1'),
    row('⚡', 'Layout in Swift',  'Flexbox engine, no CSS cascade',   '#10B981'),
    row('◐', 'Native bridges',   'Bottom sheet, haptics, alerts',     '#F59E0B'),
  ],
}

lumen.render(screen)

lumen.haptics('light')

// After a moment, raise a native iOS bottom sheet whose
// *content* is itself a Lumen view-tree.
setTimeout(() => {
  lumen.haptics('medium')

  lumen.bottomSheet({
    height: 'medium',
    content: {
      type: 'view',
      style: { flex: 1, padding: 24, gap: 16, backgroundColor: '#15151A' },
      children: [
        {
          type: 'text',
          text: 'Native iOS sheet',
          style: { fontSize: 24, fontWeight: '700', color: '#FFFFFF', height: 32 },
        },
        {
          type: 'text',
          text: 'You are looking at a UISheetPresentationController.medium detent — full iOS gesture physics, native swipe-to-dismiss. Its content (this text included) is rendered through the same Lumen pipeline as the screen behind it.',
          style: { fontSize: 14, color: '#9CA3AF', numberOfLines: 8, lineHeight: 20, height: 160 },
        },
        {
          type: 'view',
          style: {
            padding: 14,
            backgroundColor: '#6366F1',
            borderRadius: 10,
            height: 48,
          },
          children: [
            {
              type: 'text',
              text: 'Swipe down to close',
              style: {
                fontSize: 15,
                fontWeight: '600',
                color: '#FFFFFF',
                textAlign: 'center',
                height: 20,
              },
            },
          ],
        },
      ],
    },
    onClose: () => {
      console.log('user dismissed the sheet')
      lumen.haptics('soft')
    },
  })
}, 800)
