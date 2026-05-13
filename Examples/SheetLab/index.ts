// SheetLab — четыре варианта lumen.bottomSheet с разной высотой и
// разной начинкой (Lumen-rendered content внутри native sheet'а).

const lastClosed = signal<string>('—')

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    ScrollView({
      flex: 1, padding: 16, gap: 12,
      paddingBottom: 16 + lumen.safeArea.bottom,
    },
      Section('Heights',
        Button('Small (240pt)',  () => openSmall()),
        Button('Medium',         () => openMedium()),
        Button('Large',          () => openLarge()),
        Button('Full',           () => openFull()),
      ),
      Section('Rich content',
        Button('Action menu',    () => openActions()),
        Button('Form',           () => openForm()),
        Button('Story preview',  () => openStory()),
      ),
    ),
  )
}

function Header() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    backgroundColor: '#15151A', gap: 4,
  },
    Text({fontSize: 16, fontWeight: '700', color: '#FFFFFF'}, 'Sheet Lab'),
    Text({fontSize: 11, color: '#9CA3AF'},
      'lumen.bottomSheet · last closed: ' + lastClosed.value),
  )
}

// ─── presets ────────────────────────────────────────────────────────

function openSmall() {
  lumen.bottomSheet({
    height: 'small',
    content: SimpleContent('Small sheet', 'Tap outside to dismiss.'),
    onClose: () => { lastClosed.value = 'small' },
  })
}

function openMedium() {
  lumen.bottomSheet({
    height: 'medium',
    content: SimpleContent('Medium sheet', 'Default size — half-screen detent.'),
    onClose: () => { lastClosed.value = 'medium' },
  })
}

function openLarge() {
  lumen.bottomSheet({
    height: 'large',
    content: SimpleContent('Large sheet', 'Almost full-screen.'),
    onClose: () => { lastClosed.value = 'large' },
  })
}

function openFull() {
  lumen.bottomSheet({
    height: 'full',
    content: SimpleContent('Full sheet', 'Pull down to dismiss.'),
    onClose: () => { lastClosed.value = 'full' },
  })
}

function openActions() {
  lumen.bottomSheet({
    height: 'small',
    content: View({padding: 20, gap: 8},
      Text({fontSize: 18, fontWeight: '700', color: '#FFFFFF'}, 'Quick actions'),
      Text({fontSize: 12, color: '#9CA3AF', paddingBottom: 8},
        'Tap any item — sheet stays open.'),
      ActionRow('🔗', 'Copy link',     () => lumen.haptics('light')),
      ActionRow('📄', 'Open in Safari', () => lumen.haptics('light')),
      ActionRow('🔖', 'Save for later', () => lumen.haptics('success')),
    ),
    onClose: () => { lastClosed.value = 'actions' },
  })
}

function openForm() {
  lumen.bottomSheet({
    height: 'medium',
    content: View({padding: 20, gap: 12},
      Text({fontSize: 18, fontWeight: '700', color: '#FFFFFF'}, 'Quick form'),
      Text({fontSize: 12, color: '#9CA3AF'},
        'TextInput inside a sheet — focus pulls keyboard up.'),
      TextInput({
        value: '',
        placeholder: 'Title',
        height: 44, paddingLeft: 14, paddingRight: 14, fontSize: 15,
        color: '#FFFFFF',
        backgroundColor: '#1A1A20',
        borderColor: '#27272F',
        borderWidth: 1,
        borderRadius: 10,
        onChange: () => {},
      }),
      TextInput({
        value: '',
        placeholder: 'Note',
        height: 44, paddingLeft: 14, paddingRight: 14, fontSize: 15,
        color: '#FFFFFF',
        backgroundColor: '#1A1A20',
        borderColor: '#27272F',
        borderWidth: 1,
        borderRadius: 10,
        onChange: () => {},
      }),
    ),
    onClose: () => { lastClosed.value = 'form' },
  })
}

function openStory() {
  lumen.bottomSheet({
    height: 'large',
    content: ScrollView({padding: 20, gap: 12},
      Text({fontSize: 22, fontWeight: '700', color: '#FFFFFF', lineHeight: 28},
        'Lumen reaches first dogfood milestone'),
      Text({fontSize: 12, color: '#9CA3AF'},
        '2 min read · Engineering blog'),
      Text({fontSize: 15, color: '#D1D5DB', lineHeight: 22},
        'Today we shipped the foundational primitives for writing a browser ' +
        'shell on the Lumen runtime itself: TextInput, ScrollView, reactive ' +
        'safe-area, Liquid Glass, absolute positioning, multi-tab model ' +
        '(`TabsStore` + `lumen.tabs.*` bridges).'),
      Text({fontSize: 15, color: '#D1D5DB', lineHeight: 22},
        'Together they unlock a full reproduction of the iOS browser feel — ' +
        'sticky search bars, glass pills floating over scrolling content, ' +
        'tab switcher, custom Home pages — all rendered through CALayer at ' +
        '120fps on real hardware.'),
      Text({fontSize: 15, color: '#D1D5DB', lineHeight: 22},
        'Next step: pull the SwiftUI shell out and let a fast-app render the ' +
        'browser chrome itself. Eat your own dogfood.'),
    ),
    onClose: () => { lastClosed.value = 'story' },
  })
}

// ─── building blocks ───────────────────────────────────────────────

function SimpleContent(title: string, body: string): RenderNode {
  return View({padding: 20, gap: 8, justifyContent: 'center', alignItems: 'center'},
    Text({fontSize: 18, fontWeight: '700', color: '#FFFFFF'}, title),
    Text({fontSize: 13, color: '#9CA3AF', textAlign: 'center'}, body),
  )
}

function Section(title: string, ...rows: RenderNode[]) {
  return View({gap: 8},
    Text({fontSize: 11, fontWeight: '700', color: '#A5B4FC'},
      title.toUpperCase()),
    ...rows,
  )
}

function Button(label: string, onTap: () => void) {
  return Pressable({
    height: 44,
    backgroundColor: '#1E40AF',
    borderRadius: 10,
    justifyContent: 'center', alignItems: 'center',
    onTap,
  },
    Text({fontSize: 14, fontWeight: '600', color: '#FFFFFF'}, label),
  )
}

function ActionRow(icon: string, label: string, onTap: () => void) {
  return Pressable({
    flexDirection: 'row',
    paddingTop: 12, paddingBottom: 12, paddingLeft: 8, paddingRight: 8,
    borderRadius: 8,
    alignItems: 'center',
    gap: 12,
    onTap,
  },
    Text({fontSize: 18}, icon),
    Text({fontSize: 14, color: '#FFFFFF', flex: 1}, label),
  )
}

mount(App)
