// Map Lab — нативный MKMapView через мост.
//
// Демонстрирует:
//  • <MapView/> с region, pins, mapType — обычные props
//  • onRegionChange — JS callback из MKMapViewDelegate
//  • onPinTap → bottomSheet (cross-bridge композиция)
//  • mapType переключается chip'ами, регион/пины — signal'ы
//
// Хук в нативку с обеих сторон: Swift делает SetRegion/addAnnotation,
// нам обратно прилетают coordinate-события.

interface Pin {
  id: string
  lat: number
  lon: number
  title: string
}

interface Region {
  lat: number
  lon: number
  latDelta: number
  lonDelta: number
}

const SF: Region = { lat: 37.7749, lon: -122.4194, latDelta: 0.10, lonDelta: 0.10 }

const region = signal<Region>(SF)
const mapType = signal<'standard' | 'satellite' | 'hybrid'>('standard')

const pins = signal<Pin[]>([
  {id: 'ferry',  lat: 37.7955, lon: -122.3937, title: 'Ferry Building'},
  {id: 'goldengate', lat: 37.8199, lon: -122.4783, title: 'Golden Gate'},
  {id: 'mission', lat: 37.7599, lon: -122.4148, title: 'Mission District'},
])

// ─── app ────────────────────────────────────────────────

function App() {
  return View({flex: 1, backgroundColor: '#0B0B0F'},
    Body(),
    HUD(),
  )
}

function Body() {
  return MapView({
    flex: 1,
    region: region.value,
    pins: pins.value,
    mapType: mapType.value,
    onRegionChange: (r: Region) => { region.value = r },
    onPinTap: (id: string) => {
      const pin = pins.value.find(p => p.id === id)
      if (!pin) return
      lumen.haptics('soft')
      lumen.bottomSheet({
        height: 'small',
        content: View({padding: 24, gap: 8},
          Text({fontSize: 22, fontWeight: '700', color: '#ECECEE'}, pin.title),
          Text({fontSize: 12, color: '#9A9AA5'},
            `${pin.lat.toFixed(4)}, ${pin.lon.toFixed(4)}`),
        ),
      })
    },
  })
}

// ─── floating HUD ───────────────────────────────────────

function HUD() {
  return View({
    position: 'absolute',
    top: lumen.safeArea.top + 12,
    left: 16, right: 16,
    gap: 8,
  },
    HUDPill(),
    MapTypeChips(),
  )
}

function HUDPill() {
  return View({
    paddingTop: 10, paddingBottom: 10,
    paddingLeft: 14, paddingRight: 14,
    borderRadius: 16,
    backgroundColor: '#0B0B0FCC',
    borderColor: '#FFFFFF1F', borderWidth: 0.5,
  },
    Text({fontSize: 11, color: '#7FB8FF', fontWeight: '700'},
      'MAP LAB · NATIVE MKMAPVIEW'),
    Text({fontSize: 12, color: '#ECECEE', fontWeight: '500'},
      () => `${region.value.lat.toFixed(3)}, ${region.value.lon.toFixed(3)} · zoom ${(1 / region.value.latDelta).toFixed(1)}`),
  )
}

function MapTypeChips() {
  return View({flexDirection: 'row', gap: 6},
    Chip('standard',  'Std'),
    Chip('satellite', 'Sat'),
    Chip('hybrid',    'Hyb'),
    AddPinChip(),
  )
}

function Chip(type: 'standard' | 'satellite' | 'hybrid', label: string) {
  return Pressable({
    paddingTop: 6, paddingBottom: 6,
    paddingLeft: 12, paddingRight: 12,
    borderRadius: 12,
    backgroundColor: () => mapType.value === type ? '#FFFFFF' : '#0B0B0FCC',
    borderColor: '#FFFFFF1F', borderWidth: 0.5,
    onTap: () => {
      mapType.value = type
      lumen.haptics('light')
    },
  },
    Text({fontSize: 11, fontWeight: '700',
          color: () => mapType.value === type ? '#0B0B0F' : '#ECECEE'},
      label),
  )
}

function AddPinChip() {
  return Pressable({
    flex: 1,
    paddingTop: 6, paddingBottom: 6,
    paddingLeft: 12, paddingRight: 12,
    borderRadius: 12,
    backgroundColor: '#B69CFF',
    alignItems: 'center',
    onTap: () => {
      const r = region.value
      const jitter = () => (Math.random() - 0.5) * 0.4
      const pin: Pin = {
        id: 'p' + Date.now(),
        lat: r.lat + jitter() * r.latDelta,
        lon: r.lon + jitter() * r.lonDelta,
        title: 'Pin ' + (pins.value.length + 1),
      }
      pins.value = [...pins.value, pin]
      lumen.haptics('success')
    },
  },
    Text({fontSize: 11, fontWeight: '700', color: '#0B0B0F'},
      '+ Drop pin here'),
  )
}

mount(App)
