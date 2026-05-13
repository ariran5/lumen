// GlassLab — sticky Glass-pill поверх скроллящегося разноцветного фона.
// Pill зафиксирован через position: absolute, скролл двигает stripes под
// ним → видно как UIGlassEffect реагирует на изменение цвета под собой.

const palette: Color[] = [
  '#F97316', '#10B981', '#3B82F6', '#EC4899', '#FACC15',
  '#8B5CF6', '#EF4444', '#14B8A6', '#F59E0B', '#22C55E',
]

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    Stage(),
  )
}

function Header() {
  return View({
    paddingTop: 14, paddingBottom: 14,
    paddingLeft: 16, paddingRight: 16,
    backgroundColor: '#15151A',
    gap: 4,
  },
    Text({fontSize: 16, fontWeight: '700', color: '#FFFFFF'},
      'Glass Lab'),
    Text({fontSize: 11, color: '#9CA3AF'},
      'scroll the stripes — pill stays, glass adapts'),
  )
}

function Stage() {
  return View({flex: 1},
    ScrollView({flex: 1, paddingTop: 8, paddingBottom: 16 + lumen.safeArea.bottom},
      ...palette.flatMap((c, i) => [
        Stripe(c, palette[(i + 1) % palette.length]),
      ]),
    ),
    // Sticky overlay поверх ScrollView — position: absolute не участвует
    // в column flow родителя, проявляется на screen-coords parent'а.
    View({
      position: 'absolute',
      top: 20, left: 20, right: 20,
      gap: 10,
    },
      Glass({
        variant: 'regular',
        paddingTop: 14, paddingBottom: 14,
        paddingLeft: 18, paddingRight: 18,
        borderRadius: 22,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
      },
        Text({fontSize: 15, fontWeight: '700', color: '#0F0F12'},
          'Glass · regular'),
      ),
      Glass({
        variant: 'clear',
        paddingTop: 14, paddingBottom: 14,
        paddingLeft: 18, paddingRight: 18,
        borderRadius: 22,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
      },
        Text({fontSize: 15, fontWeight: '700', color: '#FFFFFF'},
          'Glass · clear'),
      ),
    ),
  )
}

function Stripe(a: Color, b: Color) {
  return View({height: 140, flexDirection: 'row'},
    View({flex: 1, backgroundColor: a}),
    View({flex: 1, backgroundColor: b}),
  )
}

mount(App)
