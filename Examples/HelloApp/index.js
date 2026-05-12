// ─────────────────────────────────────────────────────────────────
// Hello Lumen — example fast-app
//
// Fetched from your laptop, evaluated in JSContext, paints the UI
// through CALayer. Tap any row to fire native haptics + present
// a UISheetPresentationController whose content is itself a
// Lumen view-tree.
// ─────────────────────────────────────────────────────────────────

console.log('hello lumen — entry script running')

const features = [
  {
    accent: '#6366F1',
    title: 'Native primitives',
    subtitle: 'CALayer per node, GPU-composited',
    body: 'Every visible element is a real CALayer, not a UIView wrapper. Animations run on the iOS render server, off the main thread — so even if JavaScript is busy, fades and transforms keep going at full refresh rate.'
  },
  {
    accent: '#10B981',
    title: 'Layout in Swift',
    subtitle: 'Flexbox engine, no CSS cascade',
    body: 'Layout is computed by a Flexbox subset written in pure Swift. No CSS parsing, no selector matching, no descendant invalidation. A 100-node tree lays out in well under a millisecond.'
  },
  {
    accent: '#F59E0B',
    title: 'Native bridges',
    subtitle: 'Bottom sheet, haptics, alerts',
    body: 'JavaScript calls iOS APIs directly through narrow Swift shims — no async bridge, no message queues. Bottom sheet is a real UISheetPresentationController with system swipe-to-dismiss physics.'
  },
]

function row(feature) {
  return {
    type: 'view',
    onTap: () => openDetails(feature),
    style: {
      flexDirection: 'row',
      padding: 14,
      gap: 14,
      height: 72,
      backgroundColor: '#1C1C22',
      borderRadius: 14,
    },
    children: [
      {
        type: 'view',
        style: { width: 44, height: 44, borderRadius: 22, backgroundColor: feature.accent },
      },
      {
        type: 'view',
        style: { flex: 1, gap: 4, height: 44 },
        children: [
          {
            type: 'text',
            text: feature.title,
            style: { fontSize: 16, fontWeight: '600', color: '#FFFFFF', height: 22 },
          },
          {
            type: 'text',
            text: feature.subtitle,
            style: { fontSize: 12, color: '#9CA3AF', height: 16 },
          },
        ],
      },
      {
        type: 'text',
        text: '›',
        style: {
          fontSize: 24,
          color: '#4B5563',
          width: 16,
          height: 30,
          textAlign: 'center',
        },
      },
    ],
  }
}

function openDetails(feature) {
  lumen.haptics('light')

  lumen.bottomSheet({
    height: 'medium',
    content: {
      type: 'view',
      style: { flex: 1, padding: 24, gap: 14, backgroundColor: '#15151A' },
      children: [
        {
          type: 'view',
          style: {
            width: 56,
            height: 56,
            borderRadius: 28,
            backgroundColor: feature.accent,
          },
        },
        {
          type: 'text',
          text: feature.title,
          style: { fontSize: 24, fontWeight: '700', color: '#FFFFFF', height: 32 },
        },
        {
          type: 'text',
          text: feature.body,
          style: {
            fontSize: 14,
            color: '#9CA3AF',
            numberOfLines: 8,
            lineHeight: 20,
            height: 160,
          },
        },
        {
          type: 'view',
          onTap: () => {
            lumen.haptics('success')
            lumen.alert({
              title: 'Got it',
              message: 'You tapped a Pressable inside a bottom sheet, which fired native haptics through the runtime bridge. The whole chain is JavaScript → Swift in one synchronous call.',
            })
          },
          style: {
            padding: 14,
            backgroundColor: feature.accent,
            borderRadius: 10,
            height: 48,
          },
          children: [
            {
              type: 'text',
              text: 'Tap me too',
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
      console.log('sheet closed for:', feature.title)
      lumen.haptics('soft')
    },
  })
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
      text: 'This screen is rendered by a JS bundle served from your laptop. Each row is a real Pressable — tap to fire native haptics and open a UISheetPresentationController.',
      style: { fontSize: 13, color: '#9CA3AF', numberOfLines: 3, lineHeight: 18, height: 56 },
    },
    ...features.map(row),
    {
      type: 'text',
      text: 'Tap any row to see details',
      style: {
        fontSize: 11,
        color: '#6B7280',
        textAlign: 'center',
        height: 16,
      },
    },
  ],
}

lumen.render(screen)
lumen.haptics('light')
