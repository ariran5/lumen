// Story rail — horizontal "stories" row under the header. Lumen has no
// horizontal ScrollView (UIScrollView is vertical), so we show the first
// N stories visible and the rest collapses into "Ещё".
// Tap is a stub via alert for now.

import { colors, radius, space } from '../lib/colors'
import { stories, type Story } from '../state/stories'

/** How many previews fit in the row at iPhone 17 Pro width. */
const VISIBLE = 4
const AVATAR = 56

export function StoryRail(): RenderNode {
  return Slot({}, () => {
    const list = stories.value
    const head = list.slice(0, VISIBLE)
    const tail = list.length - head.length
    const cells: RenderNode[] = head.map(storyCell)
    if (tail > 0) cells.push(moreCell(tail))
    return View(
      {
        flexDirection: 'row',
        gap: space.md,
        paddingLeft: space.lg,
        paddingRight: space.lg,
      },
      ...cells,
    )
  })
}

function storyCell(s: Story): RenderNode {
  return Pressable(
    {
      key: 'story-' + s.id,
      onTap: () => {
        lumen.haptics('soft')
        if (s.preview) {
          lumen.alert({ title: s.label.replace('\n', ' '), message: s.preview })
        }
      },
      width: AVATAR + 4,
      alignItems: 'center',
      gap: 6,
    },
    // Ring + avatar — Pressable receives taps on both.
    View(
      {
        width: AVATAR + 4,
        height: AVATAR + 4,
        borderRadius: (AVATAR + 4) / 2,
        backgroundColor: s.seen ? colors.divider : s.ringColor,
        alignItems: 'center',
        justifyContent: 'center',
        opacity: s.seen ? 0.55 : 1,
      },
      View(
        {
          width: AVATAR,
          height: AVATAR,
          borderRadius: AVATAR / 2,
          backgroundColor: s.bg,
          alignItems: 'center',
          justifyContent: 'center',
          borderWidth: 2,
          borderColor: colors.bg,
        },
        Text({ fontSize: 26 }, s.icon),
      ),
    ),
    Text(
      {
        fontSize: 11,
        fontWeight: '500',
        color: colors.textSecondary,
        textAlign: 'center',
        numberOfLines: 2,
        lineHeight: 13,
        width: AVATAR + 8,
      },
      s.label,
    ),
  )
}

function moreCell(count: number): RenderNode {
  return Pressable(
    {
      key: 'story-more',
      onTap: () => {
        lumen.haptics('soft')
        lumen.alert({ title: 'Истории', message: `Ещё ${count} новых истории в Tinkoff Pro.` })
      },
      width: AVATAR + 4,
      alignItems: 'center',
      gap: 6,
    },
    View(
      {
        width: AVATAR + 4,
        height: AVATAR + 4,
        borderRadius: (AVATAR + 4) / 2,
        backgroundColor: colors.surfaceElevated,
        alignItems: 'center',
        justifyContent: 'center',
        borderWidth: 1,
        borderColor: colors.border,
      },
      Text({ fontSize: 22, color: colors.textPrimary }, '+' + count),
    ),
    Text(
      { fontSize: 11, fontWeight: '500', color: colors.textSecondary, textAlign: 'center' },
      'Ещё',
    ),
  )
}
