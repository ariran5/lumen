// InputLab — проверка TextInput для будущего shell'а.
//
// Минимальный набор: одиночное поле (имя), URL-поле с onSubmit, password.
// Шапка показывает live-значения, чтобы видно было что controlled-value
// работает и onChange приходит на каждом нажатии.

const name = signal('')
const urlInput = signal('https://')
const password = signal('')
const lastSubmit = signal<string>('—')

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    NamePanel(),
    URLPanel(),
    SecurePanel(),
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
      'Input Lab'),
    Text({fontSize: 11, color: '#9CA3AF'},
      `hello, ${name.value || '…'} · submitted: ${lastSubmit.value}`),
  )
}

function NamePanel() {
  return View({
    paddingTop: 18, paddingLeft: 16, paddingRight: 16, gap: 8,
  },
    Label('Name'),
    TextInput({
      value: name.value,
      placeholder: 'Your name',
      autocapitalize: 'words',
      backgroundColor: '#1A1A20',
      borderColor: '#27272F',
      borderWidth: 1,
      borderRadius: 10,
      height: 44,
      paddingLeft: 14, paddingRight: 14,
      fontSize: 15,
      color: '#FFFFFF',
      onChange: (e) => { name.value = e.value },
    }),
  )
}

function URLPanel() {
  return View({
    paddingTop: 14, paddingLeft: 16, paddingRight: 16, gap: 8,
  },
    Label('URL (Return → submit)'),
    TextInput({
      value: urlInput.value,
      placeholder: 'https://…',
      keyboardType: 'url',
      returnKey: 'go',
      autocapitalize: 'none',
      autocorrect: false,
      backgroundColor: '#1A1A20',
      borderColor: '#27272F',
      borderWidth: 1,
      borderRadius: 10,
      height: 44,
      paddingLeft: 14, paddingRight: 14,
      fontSize: 15,
      color: '#FFFFFF',
      onChange: (e) => { urlInput.value = e.value },
      onSubmit: (e) => {
        lastSubmit.value = e.value
        lumen.haptics('success')
      },
    }),
  )
}

function SecurePanel() {
  return View({
    paddingTop: 14, paddingLeft: 16, paddingRight: 16, gap: 8,
  },
    Label('Password'),
    TextInput({
      value: password.value,
      placeholder: 'Password',
      secure: true,
      autocapitalize: 'none',
      autocorrect: false,
      backgroundColor: '#1A1A20',
      borderColor: '#27272F',
      borderWidth: 1,
      borderRadius: 10,
      height: 44,
      paddingLeft: 14, paddingRight: 14,
      fontSize: 15,
      color: '#FFFFFF',
      onChange: (e) => { password.value = e.value },
    }),
    Text({fontSize: 11, color: '#6B7280'},
      `${password.value.length} chars`),
  )
}

function Label(text: string) {
  return Text({fontSize: 12, fontWeight: '600', color: '#A5B4FC'}, text)
}

mount(App)
