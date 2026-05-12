// ─────────────────────────────────────────────────────────────────
// Hacker News reader, built on Lumen
//
// Demonstrates the full stack working together:
//   fetch         → top stories + per-story details
//   virtualList   → recycled CALayer cells, 60fps scroll
//   image         → favicons fetched from Google's favicon API
//   text          → CoreText shaping, truncation
//   onTap         → tap a row to open native sheet
//   bottomSheet   → UISheetPresentationController with Lumen content
//   haptics       → tap feedback
// ─────────────────────────────────────────────────────────────────

const HN = 'https://hacker-news.firebaseio.com/v0'
let stories = []

renderPlaceholder('Fetching top stories…')

// Sequential loader — Promise.all with parallel fetches currently
// has a concurrency bug in the JSC ↔ URLSession bridge. Sequential
// chaining works reliably.
function loadSequentially(ids, idx, acc) {
  if (idx >= ids.length) return Promise.resolve(acc)
  return fetch(`${HN}/item/${ids[idx]}.json`)
    .then(r => r.json())
    .then(item => {
      if (item) acc.push(item)
      renderPlaceholder('Loading stories… ' + (idx + 1) + '/' + ids.length)
      return loadSequentially(ids, idx + 1, acc)
    })
    .catch(() => loadSequentially(ids, idx + 1, acc))
}

fetch(`${HN}/topstories.json`)
  .then(r => r.json())
  .then(ids => {
    const top = ids.slice(0, 20)
    return loadSequentially(top, 0, [])
  })
  .then(items => {
    renderPlaceholder('Mounting list with ' + items.length + ' items…')
    stories = items
      .filter(s => s && s.title)
      .map(s => ({
        id: s.id,
        title: s.title || '(untitled)',
        by: s.by || 'anon',
        score: s.score || 0,
        descendants: s.descendants || 0,
        url: s.url || '',
        time: s.time || 0,
        hostname: hostnameOf(s.url),
      }))
    mountList()
    lumen.haptics('soft')
  })
  .catch(err => {
    renderPlaceholder('Load failed: ' + (err && err.message ? err.message : String(err)))
    lumen.haptics('error')
  })

function hostnameOf(url) {
  if (!url) return ''
  const m = url.match(/^https?:\/\/([^\/]+)/)
  return m ? m[1] : ''
}

function faviconURL(host) {
  if (!host) return ''
  return `https://www.google.com/s2/favicons?domain=${host}&sz=64`
}

function timeAgo(t) {
  const sec = Math.max(0, Math.floor(Date.now() / 1000 - t))
  if (sec < 60) return sec + 's ago'
  if (sec < 3600) return Math.floor(sec / 60) + 'm ago'
  if (sec < 86400) return Math.floor(sec / 3600) + 'h ago'
  return Math.floor(sec / 86400) + 'd ago'
}

function renderPlaceholder(message) {
  lumen.render({
    type: 'view',
    style: { flex: 1, padding: 32, gap: 12, backgroundColor: '#0F0F12' },
    children: [
      {
        type: 'text',
        text: 'Hacker News',
        style: { fontSize: 28, fontWeight: '700', color: '#FFFFFF', height: 36 },
      },
      {
        type: 'text',
        text: message,
        style: { fontSize: 14, color: '#9CA3AF', height: 22 },
      },
    ],
  })
}

function mountList() {
  lumen.virtualList({
    count: stories.length,
    itemHeight: 88,
    render: renderRow,
  })
}

function renderRow(i) {
  const s = stories[i]
  return {
    type: 'view',
    onTap: () => openStory(s),
    style: {
      flexDirection: 'row',
      padding: 14,
      gap: 12,
      height: 88,
      backgroundColor: i % 2 === 0 ? '#15151A' : '#1A1A20',
    },
    children: [
      {
        type: 'view',
        style: {
          width: 32, height: 32, borderRadius: 8,
          backgroundColor: '#27272F',
          padding: 4,
        },
        children: s.hostname ? [{
          type: 'image',
          source: faviconURL(s.hostname),
          style: { flex: 1, contentMode: 'contain' },
        }] : [],
      },
      {
        type: 'view',
        style: { flex: 1, gap: 4, height: 60 },
        children: [
          {
            type: 'text',
            text: s.title,
            style: {
              fontSize: 14,
              fontWeight: '600',
              color: '#FFFFFF',
              numberOfLines: 2,
              lineHeight: 18,
              height: 36,
            },
          },
          {
            type: 'text',
            text: s.score + ' · ' + s.descendants + ' comments · ' + (s.hostname || 'self') + ' · ' + timeAgo(s.time),
            style: {
              fontSize: 11,
              color: '#9CA3AF',
              height: 16,
              numberOfLines: 1,
            },
          },
        ],
      },
    ],
  }
}

function openStory(s) {
  lumen.haptics('light')
  lumen.router.push({
    title: s.hostname || 'Story',
    render: () => renderStoryDetail(s),
    onPop: () => lumen.haptics('soft'),
  })
}

function renderStoryDetail(s) {
  return {
    type: 'view',
    style: { flex: 1, padding: 24, gap: 16, backgroundColor: '#0F0F12' },
    children: [
      {
        type: 'view',
        style: { flexDirection: 'row', gap: 12, height: 64 },
        children: [
          {
            type: 'view',
            style: { width: 64, height: 64, borderRadius: 14, backgroundColor: '#27272F', padding: 8 },
            children: s.hostname ? [{
              type: 'image',
              source: faviconURL(s.hostname),
              style: { flex: 1, contentMode: 'contain' },
            }] : [],
          },
          {
            type: 'view',
            style: { flex: 1, gap: 4, height: 64 },
            children: [
              { type: 'text', text: s.hostname || 'news.ycombinator.com',
                style: { fontSize: 13, fontWeight: '600', color: '#FFFFFF', height: 18 } },
              { type: 'text', text: 'by ' + s.by,
                style: { fontSize: 12, color: '#9CA3AF', height: 16 } },
              { type: 'text', text: timeAgo(s.time),
                style: { fontSize: 12, color: '#9CA3AF', height: 16 } },
            ],
          },
        ],
      },
      {
        type: 'text',
        text: s.title,
        style: {
          fontSize: 22,
          fontWeight: '700',
          color: '#FFFFFF',
          numberOfLines: 6,
          lineHeight: 28,
          height: 170,
        },
      },
      {
        type: 'view',
        style: { flexDirection: 'row', gap: 10, height: 36 },
        children: [
          { type: 'view',
            style: { paddingTop: 8, paddingRight: 14, paddingBottom: 8, paddingLeft: 14,
                     backgroundColor: '#27272F', borderRadius: 10, height: 34 },
            children: [{ type: 'text', text: '▲ ' + s.score + ' points',
                        style: { fontSize: 13, fontWeight: '600', color: '#FBBF24', height: 18 } }] },
          { type: 'view',
            onTap: () => {
              lumen.haptics('medium')
              lumen.router.push({
                title: 'Comments',
                render: () => renderCommentsPlaceholder(s),
              })
            },
            style: { paddingTop: 8, paddingRight: 14, paddingBottom: 8, paddingLeft: 14,
                     backgroundColor: '#27272F', borderRadius: 10, height: 34 },
            children: [{ type: 'text', text: '💬 ' + s.descendants + ' comments',
                        style: { fontSize: 13, fontWeight: '600', color: '#A5B4FC', height: 18 } }] },
        ],
      },
      {
        type: 'view',
        onTap: () => {
          lumen.haptics('success')
          lumen.alert({
            title: s.title,
            message: 'In a real reader, tapping this would open ' + (s.url || 'the HN thread'),
          })
        },
        style: {
          paddingTop: 14, paddingRight: 18, paddingBottom: 14, paddingLeft: 18,
          backgroundColor: '#6366F1',
          borderRadius: 12,
          height: 50,
        },
        children: [{
          type: 'text',
          text: 'Open article',
          style: { fontSize: 15, fontWeight: '600', color: '#FFFFFF', textAlign: 'center', height: 22 },
        }],
      },
    ],
  }
}

function renderCommentsPlaceholder(s) {
  return {
    type: 'view',
    style: { flex: 1, padding: 24, gap: 12, backgroundColor: '#0F0F12' },
    children: [
      {
        type: 'text',
        text: s.descendants + ' comments',
        style: { fontSize: 24, fontWeight: '700', color: '#FFFFFF', height: 32 },
      },
      {
        type: 'text',
        text: 'You navigated three levels deep through native UINavigationController — swipe from the left edge to pop back. Each page has its own JS-driven CALayer tree.',
        style: { fontSize: 14, color: '#9CA3AF', numberOfLines: 6, lineHeight: 20, height: 120 },
      },
    ],
  }
}
