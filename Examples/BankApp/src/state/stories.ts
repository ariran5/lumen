// Stories row under the home header — copies the familiar T-Bank
// format: round previews with a colored ring; tap opens a sheet
// with details (TODO — for now just haptics + alert).

export interface Story {
  id: string
  /** Emoji in the circle. */
  icon: string
  /** Caption under the circle (max 2 lines). */
  label: string
  /** Ring color. */
  ringColor: string
  /** Circle background. */
  bg: string
  /** Text for the preview-alert on tap (stub). */
  preview?: string
  /** Whether it has been viewed — drives the ring opacity. */
  seen?: boolean
}

export const stories = signal<Story[]>([
  {
    id: 'cashback',
    icon: '🔥',
    label: 'Кэшбэк\nмая',
    ringColor: '#FFDD2D',
    bg: '#3D3618',
    preview: 'Категории кэшбэка на май: рестораны 5%, такси 5%, заправки 3%.',
  },
  {
    id: 'rates',
    icon: '💱',
    label: 'Курсы\nвалют',
    ringColor: '#4ADE80',
    bg: '#1B2A22',
    preview: 'USD 92,4 · EUR 100,1 · CNY 12,8',
  },
  {
    id: 'partners',
    icon: '🎁',
    label: 'Подарки\nпартнёров',
    ringColor: '#FFB347',
    bg: '#2C2218',
    preview: 'Скидки до 40% у партнёров Tinkoff Pro.',
  },
  {
    id: 'travel',
    icon: '🛫',
    label: 'Travel\nсейчас',
    ringColor: '#A78BFA',
    bg: '#231B2E',
    preview: 'Билеты в Стамбул со скидкой 25% до конца недели.',
  },
  {
    id: 'invest',
    icon: '📊',
    label: 'Идеи\nдня',
    ringColor: '#60A5FA',
    bg: '#1A2230',
    preview: 'Сбер дивиденды: 33,3 ₽ на акцию, отсечка 12 июля.',
    seen: true,
  },
  {
    id: 'pro',
    icon: '⭐',
    label: 'Tinkoff\nPro',
    ringColor: '#FFDD2D',
    bg: '#2A2410',
    preview: 'Активируйте подписку Pro и получайте до 30% кэшбэка.',
    seen: true,
  },
])
