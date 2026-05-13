// DragLab — все жесты Lumen в одном демо.
//
//   • Drag area (Pan) — координаты пальца + шарик через transform
//   • Tap zones — single tap + long press (double tap пока отключён)
//   • Swipe area — left/right/up/down
//   • Pinch + rotate — двумя пальцами

const ballX = signal(0)
const ballY = signal(0)
const panState = signal('—')

// Snap-back ball: AnimatedValue двигается на render-сервере,
// не дёргает реактивный re-render. На drag-end летит обратно spring'ом
// в (0,0); если схватить пальцем в полёте — .stop() фиксирует
// presentation-value и шарик слушается пальца с этого места.
const snapX = animated(0)
const snapY = animated(0)
const snapInFlight = signal(false)

const tapCount = signal(0)
const longCount = signal(0)

const lastSwipe = signal<string>('—')

const pinchScale = signal(1)
const rotation = signal(0)

const lastEvent = signal<string>('waiting…')

function note(msg: string) {
  lastEvent.value = msg
}

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    DiagBar(),
    DragArea(),
    SnapArea(),
    TapPanel(),
    SwipePanel(),
    PinchPanel(),
  )
}

function Header() {
  return View({
    flexDirection: 'row', alignItems: 'center',
    paddingTop: 12, paddingBottom: 12, paddingLeft: 16, paddingRight: 16,
    backgroundColor: '#15151A',
  },
    Text({flex: 1, fontSize: 16, fontWeight: '700', color: '#FFFFFF'},
      'Drag Lab'),
    Text({fontSize: 11, color: '#9CA3AF'}, 'all gestures →'),
  )
}

function DiagBar() {
  return View({
    paddingTop: 6, paddingBottom: 6, paddingLeft: 16, paddingRight: 16,
    backgroundColor: '#1F2937',
  },
    Text({fontSize: 11, fontWeight: '600', color: '#FBBF24'},
      'last: ' + lastEvent.value),
  )
}

// ─── pan ───────────────────────────────────────────────────────────

function DragArea() {
  return View({
    height: 200,
    backgroundColor: '#1A1A20',
    borderColor: '#27272F',
    borderWidth: 1,
    onPan: (e) => {
      if (e.state === 'start' || e.state === 'changed') {
        ballX.value = e.x - 30
        ballY.value = e.y - 30
      }
      panState.value = e.state
      note(`pan ${e.state} dxdy=(${Math.round(e.dx)}, ${Math.round(e.dy)})`)
    },
  },
    View({paddingTop: 8, paddingLeft: 14},
      Text({fontSize: 11, color: '#9CA3AF'},
        `pan ${panState.value} → ball (${Math.round(ballX.value)}, ${Math.round(ballY.value)})`),
    ),
    View({
      width: 60, height: 60, borderRadius: 30,
      backgroundColor: '#6366F1',
      transform: {translateX: ballX.value, translateY: ballY.value},
    }),
  )
}

// ─── snap-back (AnimatedValue) ─────────────────────────────────────

function SnapArea() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    gap: 8, backgroundColor: '#0F0F12',
  },
    Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC'},
      'Snap-back ball — spring on release, catch mid-flight'),
    View({
      height: 180,
      backgroundColor: '#1A1A20',
      borderColor: '#27272F',
      borderWidth: 1,
      borderRadius: 10,
      onPan: (e) => {
        if (e.state === 'start') {
          // Ловим в полёте: presentation-value становится новой моделью.
          snapX.stop()
          snapY.stop()
          snapInFlight.value = false
          // dx/dy от UIPan начинаются с (0,0) на каждый pan, поэтому
          // запоминаем «откуда» через snapX.current() при start, и в
          // changed считаем absolute = start + dx.
          dragStartX = snapX.current()
          dragStartY = snapY.current()
          snapX.set(dragStartX)
          snapY.set(dragStartY)
          note(`snap drag start @ (${dragStartX|0}, ${dragStartY|0})`)
        } else if (e.state === 'changed') {
          snapX.set(dragStartX + e.dx)
          snapY.set(dragStartY + e.dy)
        } else if (e.state === 'ended' || e.state === 'cancelled') {
          snapInFlight.value = true
          snapX.animateTo(0, {easing: 'spring'})
          snapY.animateTo(0, {easing: 'spring'})
          note(`snap release vx=${e.vx|0} vy=${e.vy|0} → spring home`)
        }
      },
    },
      View({paddingTop: 8, paddingLeft: 14},
        Text({fontSize: 11, color: '#9CA3AF'},
          snapInFlight.value
            ? 'flying home — grab it mid-air'
            : 'drag the orange ball; release to spring back'),
      ),
      View({
        width: 60, height: 60, borderRadius: 30,
        backgroundColor: '#F59E0B',
        transform: {translateX: snapX, translateY: snapY},
      }),
    ),
  )
}

let dragStartX = 0
let dragStartY = 0

// ─── tap / long press ──────────────────────────────────────────────

function TapPanel() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    gap: 8, backgroundColor: '#0F0F12',
  },
    Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC'},
      'Tap & long press'),
    View({flexDirection: 'row', gap: 12},
      TapBox('Tap', '#27272F', {
        onTap: (e) => {
          tapCount.value++
          note(`tap @ (${Math.round(e.x)}, ${Math.round(e.y)})`)
          lumen.haptics('light')
        },
      }),
      TapBox('Long', '#27272F', {
        onLongPress: (e) => {
          longCount.value++
          note(`long-press @ (${Math.round(e.x)}, ${Math.round(e.y)})`)
          lumen.haptics('heavy')
        },
      }),
    ),
    Text({fontSize: 11, color: '#9CA3AF'},
      `taps ${tapCount.value} · long ${longCount.value}`),
  )
}

function TapBox(label: string, bg: string, handlers: GestureProps): RenderNode {
  return View({
    flex: 1, height: 56,
    backgroundColor: bg, borderRadius: 10,
    justifyContent: 'center', alignItems: 'center',
    onTap: handlers.onTap,
    onLongPress: handlers.onLongPress,
  },
    Text({fontSize: 13, fontWeight: '600', color: '#FFFFFF'}, label),
  )
}

// ─── swipe ─────────────────────────────────────────────────────────

function SwipePanel() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    gap: 8, backgroundColor: '#0F0F12',
  },
    Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC'}, 'Swipe area'),
    View({
      height: 60,
      backgroundColor: '#27272F', borderRadius: 10,
      justifyContent: 'center', alignItems: 'center',
      onSwipe: (e) => {
        lastSwipe.value = e.direction
        note(`swipe ${e.direction}`)
        lumen.haptics('soft')
      },
    },
      Text({fontSize: 13, fontWeight: '600', color: '#10B981'},
        `last swipe: ${lastSwipe.value}`),
    ),
  )
}

// ─── pinch + rotate ────────────────────────────────────────────────

function PinchPanel() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    gap: 8, backgroundColor: '#0F0F12',
  },
    Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC'},
      'Pinch + rotate (2 fingers)'),
    View({
      height: 80,
      backgroundColor: '#27272F', borderRadius: 10,
      justifyContent: 'center', alignItems: 'center',
      onPinch: (e) => {
        pinchScale.value = e.scale
        note(`pinch ${e.state} scale=${e.scale.toFixed(2)}`)
      },
      onRotate: (e) => {
        rotation.value = e.rotation
        note(`rotate ${e.state} ${(e.rotation * 180 / Math.PI).toFixed(0)}°`)
      },
    },
      Text({fontSize: 13, fontWeight: '600', color: '#FBBF24'},
        `scale ${pinchScale.value.toFixed(2)} · rot ${(rotation.value * 180 / Math.PI).toFixed(0)}°`),
    ),
  )
}

mount(App)
