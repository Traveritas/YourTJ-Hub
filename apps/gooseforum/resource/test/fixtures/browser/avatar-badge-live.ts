import { createApp, h, defineComponent } from 'vue'
import UserAvatar from '../../../src/site/components/UserAvatar.vue'
import '../../../src/styles/resource.css'
import type { UserBadgePayload } from '@gooseforum/client'

/**
 * 徽章图标光学尺寸的方案对比页（真实组件 + 真实 resource.css）。
 *
 * 四个方案并排：
 * - before   原始图形 + 旧容器（p-[2px]，图标区占角标的比例随头像尺寸变化）
 * - iconOnly 当前图形（墨迹半径 10/24）+ 旧容器
 * - after    当前图形 + 当前 UserAvatar.vue（图标区固定占角标 88%）
 * - ratio80  图形再放大到墨迹半径 10.9/24 + 当前 UserAvatar.vue（备选参考）
 *
 * 旧容器在本页用 CSS 覆盖模拟（[data-container="legacy"]）；after / ratio80 是组件原样。
 * 每格下方的百分比是实时测得的“墨迹半径 / 角标圆半径”。
 *
 * 供 test/badge-icon-optical-size.browser.mjs 复用：带 data-badge-code / data-variant="after"
 * 的单元格是测试的测量对象，data-site 标明头像尺寸。
 */

type Meta = [code: string, name: string, description: string, color: string, level: string, sortOrder: number]

// 与 app/service/badgeservice/definitions.go 一致
const META: Meta[] = [
  ['first_post', '初次发帖', '发布了第一篇主题', 'blue', 'bronze', 10],
  ['first_comment', '初次评论', '留下了第一条评论或回复', 'teal', 'bronze', 20],
  ['first_like_given', '友善点赞', '第一次为他人的内容点赞', 'rose', 'bronze', 30],
  ['first_follower', '被看见了', '获得了第一位粉丝', 'violet', 'bronze', 40],
  ['writer_10', '持续创作', '累计发布 10 篇主题', 'sky', 'silver', 50],
  ['commenter_50', '热心讨论', '累计发布 50 条评论或回复', 'emerald', 'silver', 60],
  ['liked_10', '受到认可', '累计获得 10 个赞', 'amber', 'silver', 70],
  ['popular_100', '社区之光', '累计获得 100 个赞', 'orange', 'gold', 80],
  ['social_10', '小有名气', '累计获得 10 位粉丝', 'purple', 'silver', 90],
  ['early_member', '早期成员', '社区早期加入者', 'cyan', 'special', 100],
  ['contributor', '贡献者', '为社区建设做出贡献', 'fuchsia', 'special', 110],
  ['moderator', '社区维护者', '协助维护社区秩序', 'emerald', 'special', 120],
  ['sponsor', '赞助者', '支持社区持续运行', 'yellow', 'special', 130],
  ['king', 'King', '社区之王', 'amber', 'special', 140],
  ['robot', '机器人', '你就是机器人！', 'slate', 'special', 150],
]

const BEFORE_DIR = '/assets/test/fixtures/browser/badge-before'
// 直接用 Vite 能服务的 root 路径（与线上 /static/... 是同一批文件），
// 这样测试用裸 vite dev server 也能加载图形。
const AFTER_DIR = '/assets/static/badges'
const avatar = '/assets/static/pic/1.webp'
const FOCUS = ['first_post', 'first_comment', 'first_like_given', 'first_follower', 'liked_10']

/** ratio80 方案在当前图形基础上的额外放大：路径半径 9 → 9.9，墨迹半径 10 → 10.9。 */
const BOOST = 9.9 / 9

type Variant = 'before' | 'iconOnly' | 'after' | 'ratio80'
const VARIANTS: { key: Variant, label: string, hint: string }[] = [
  { key: 'before', label: 'A 修改前', hint: '原图形 + 旧容器（2px 内边距）' },
  { key: 'iconOnly', label: 'B 只缩图形', hint: '缩图形 + 旧容器' },
  { key: 'after', label: 'C 修改后', hint: '缩图形 + 图标区固定 88%' },
  { key: 'ratio80', label: 'D 备选 80%', hint: '略大图形 + 图标区固定 88%' },
]

const iconName = (code: string) => `${code.replace(/_/g, '-')}.svg`
const boosted = new Map<string, string>()

/** 在当前图形上叠加 BOOST 倍缩放，并同步补偿描边，生成 ratio80 用的 data URL。 */
async function buildBoosted() {
  await Promise.all(META.map(async ([code]) => {
    let svg = await (await fetch(`${AFTER_DIR}/${iconName(code)}`)).text()
    const m = svg.match(/scale\(([\d.]+)\)/)
    if (m) {
      const s = Number(m[1]) * BOOST
      svg = svg
        .replace(/scale\([\d.]+\)/, `scale(${s.toFixed(4)})`)
        .replace(/(<g [^>]*?)stroke-width="[\d.]+"/, `$1stroke-width="${(2 / s).toFixed(4)}"`)
    } else {
      svg = svg
        .replace(/(<svg[^>]*>)/, `$1<g transform="translate(12 12) scale(${BOOST.toFixed(4)}) translate(-12 -12)" stroke-width="${(2 / BOOST).toFixed(4)}">`)
        .replace(/<\/svg>\s*$/, '</g></svg>')
    }
    boosted.set(code, `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`)
  }))
}

function iconUrl(code: string, variant: Variant) {
  if (variant === 'before') return `${BEFORE_DIR}/${iconName(code)}`
  if (variant === 'ratio80') return boosted.get(code)!
  return `${AFTER_DIR}/${iconName(code)}`
}

function payload(code: string, variant: Variant): UserBadgePayload {
  const [, name, description, color, level, sortOrder] = META.find((m) => m[0] === code)!
  return {
    code, type: 'system', grantMode: 'auto', name, description,
    iconType: 'asset', iconKey: '', iconUrl: iconUrl(code, variant), color, level,
    isEnabled: true, isWearable: false, sortOrder,
    source: 'auto', reason: '', grantedAt: '2026-09-01T00:00:00Z',
  }
}

const SITES = {
  profile: {
    key: 'profile',
    label: '个人主页（h-24 / sm:h-28）',
    size: 'large' as const,
    cls: 'h-24 w-24 shrink-0 rounded-full border-2 border-base-100 bg-base-100 shadow-sm sm:h-28 sm:w-28',
    gap: '22px',
  },
  card: {
    key: 'card',
    label: '用户卡片（h-14）',
    size: 'medium' as const,
    cls: 'h-14 w-14 rounded-full',
    gap: '18px',
  },
  post: {
    key: 'post',
    label: '帖子楼层（h-9 / sm:h-10）',
    size: 'medium' as const,
    cls: 'h-9 w-9 rounded-full ring-1 ring-line sm:h-10 sm:w-10',
    gap: '16px',
  },
  reply: {
    key: 'reply',
    label: '回复行（h-6）',
    size: 'medium' as const,
    cls: 'h-6 w-6 rounded-full ring-1 ring-line',
    gap: '14px',
  },
}

type Site = (typeof SITES)[keyof typeof SITES]

const muted = 'color-mix(in oklab, var(--gf-color-base-content) 60%, transparent)'
const caption = (text: string, strong = false) =>
  h('span', {
    style: {
      fontSize: strong ? '12px' : '11px',
      fontWeight: strong ? '700' : '600',
      color: strong ? 'var(--gf-color-base-content)' : muted,
      whiteSpace: 'nowrap',
    },
  }, text)

function Avatar(code: string, site: Site, variant: Variant, extraClass = '') {
  return h(UserAvatar, {
    src: avatar, alt: code, badge: payload(code, variant), size: site.size,
    class: `${site.cls} ${extraClass}`, imgClass: 'rounded-full',
    'data-badge-code': code, 'data-variant': variant, 'data-site': site.key,
    'data-container': variant === 'before' || variant === 'iconOnly' ? 'legacy' : 'current',
    'data-measure': '',
  })
}

/** 一格：头像 + 实时测得的占比。 */
function Cell(code: string, site: Site, variant: Variant, opts: { name?: boolean, zoom?: number } = {}) {
  const zoom = opts.zoom ?? 1
  return h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '4px', minWidth: '52px' } }, [
    h('div', zoom > 1
      ? { style: { transform: `scale(${zoom})`, transformOrigin: 'center', margin: `${(zoom - 1) * 28}px ${(zoom - 1) * 28}px` } }
      : {}, Avatar(code, site, variant)),
    opts.name ? caption(META.find((m) => m[0] === code)![1], true) : null,
    h('span', { 'data-ratio-label': '', style: { fontSize: '10px', fontVariantNumeric: 'tabular-nums', color: muted } }, '…'),
  ])
}

function Section(label: string, note: string | null, children: unknown[], extra: Record<string, unknown> = {}) {
  return h('section', { class: 'gf-card', style: { marginTop: '18px', paddingBottom: '14px' }, ...extra }, [
    h('div', { style: { padding: '10px 16px 0', fontSize: '13px', fontWeight: '700' } }, label),
    note ? h('div', { style: { padding: '2px 16px 0', fontSize: '11px', color: muted } }, note) : null,
    h('div', { style: { padding: '12px 16px 0', overflowX: 'auto' } }, children),
  ])
}

/** 矩阵：行 = 方案，列 = 徽章。 */
function Matrix(codes: string[], site: Site, variants = VARIANTS) {
  return h('div', { style: { display: 'grid', gridTemplateColumns: `128px repeat(${codes.length}, max-content)`, columnGap: site.gap, rowGap: '14px', alignItems: 'center' } },
    variants.flatMap((v, i) => [
      h('div', { style: { display: 'flex', flexDirection: 'column' } }, [caption(v.label, true), caption(v.hint)]),
      ...codes.map((c) => Cell(c, site, v.key, { name: i === 0 })),
    ]))
}

/** 单个徽章在所有尺寸下的对比：行 = 尺寸，列 = 方案。 */
function SizeGrid(code: string) {
  const sites = [SITES.profile, SITES.card, SITES.post, SITES.reply]
  return h('div', { style: { display: 'grid', gridTemplateColumns: `150px repeat(${VARIANTS.length}, max-content)`, columnGap: '40px', rowGap: '18px', alignItems: 'center' } }, [
    h('span'),
    ...VARIANTS.map((v) => h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center' } }, [caption(v.label, true), caption(v.hint)])),
    ...sites.flatMap((s) => [caption(s.label, true), ...VARIANTS.map((v) => Cell(code, s, v.key))]),
  ])
}

const allCodes = META.map((m) => m[0])

const App = defineComponent({
  render: () => h('div', { class: 'font-sans', style: { minHeight: '100vh', padding: '18px 24px 40px', background: 'var(--gf-color-base-200)', color: 'var(--gf-color-base-content)' } }, [
    h('h1', { style: { fontSize: '15px', fontWeight: '700', margin: '0 0 4px' } }, '徽章图标光学尺寸 — 方案对比（真实 UserAvatar.vue 渲染）'),
    h('p', { style: { fontSize: '12px', color: muted, margin: '0 0 4px', maxWidth: '920px' } },
      'A 修改前：原始图形，角标内边距固定 2px。B 只缩图形：图形统一缩到“受到认可”的大小但容器不变——个人主页正常，小尺寸因为固定内边距额外留白而偏小。'
      + 'C 修改后：图形同 B，角标去掉 2px 内边距、图标区固定占角标的 88%（个人主页与原来相同，小尺寸的图标区从 10px 变为约 12.3px），所有尺寸下比例一致。D 是在 C 基础上图形再放大约 10% 的备选。'),
    h('p', { style: { fontSize: '12px', color: muted, margin: '0 0 12px' } },
      '每格下方百分比 = 墨迹最远点到圆心的距离 ÷ 角标圆半径（实时测量，> 100% 即画出圆框，> 80% 视为贴边）。A / B 的旧容器在本页用 CSS 模拟，C / D 是 UserAvatar.vue 原样。'),

    // 第一节必须是个人主页尺寸（测试取每个徽章第一个 after 单元格）
    Section('全部 15 个徽章 @ 个人主页', null, [Matrix(allCodes, SITES.profile)]),
    Section('被看见了 @ 全部尺寸', '同一个图标在不同尺寸下：B 列个人主页正常、小尺寸变小；C / D 列各尺寸比例一致。', [SizeGrid('first_follower')]),
    Section('全部 15 个徽章 @ 回复行 h-6', null, [Matrix(allCodes, SITES.reply)]),
    Section('全部 15 个徽章 @ 帖子楼层 h-9 / sm:h-10', null, [Matrix(allCodes, SITES.post)]),
    Section('全部 15 个徽章 @ 用户卡片 h-14', null, [Matrix(allCodes, SITES.card)]),
    Section('3× 放大：被看见了 @ h-6', null, [
      h('div', { style: { display: 'flex', gap: '24px', alignItems: 'flex-start' } },
        VARIANTS.map((v) => h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '4px' } }, [
          caption(v.label, true), Cell('first_follower', SITES.reply, v.key, { zoom: 3 }),
        ]))),
    ]),
    h('div', { 'data-theme': 'gf-dark', style: { marginTop: '18px', borderRadius: '12px', background: 'var(--gf-color-base-100)', color: 'var(--gf-color-base-content)' } }, [
      Section('深色主题 @ 个人主页', null, [Matrix(FOCUS, SITES.profile)]),
      Section('深色主题 @ 回复行 h-6', null, [Matrix(FOCUS, SITES.reply)]),
    ]),
  ]),
})

const style = document.createElement('style')
style.textContent = `
  [data-container="legacy"] > span.absolute { padding: 2px !important; }
  [data-container="legacy"] > span.absolute > img { width: 100% !important; height: 100% !important; }
`
document.head.appendChild(style)

/** 实时测量每格的“墨迹半径 / 角标圆半径”，算法与 badge-icon-optical-size.browser.mjs 一致。 */
async function measureAll() {
  const N = 480
  const unit = 24 / N
  const cache = new Map<string, Promise<number>>()
  const inkRadius = (src: string) => {
    if (!cache.has(src)) {
      cache.set(src, (async () => {
        const img = new Image()
        img.src = src
        await img.decode()
        const canvas = document.createElement('canvas')
        canvas.width = N
        canvas.height = N
        const ctx = canvas.getContext('2d', { willReadFrequently: true })!
        ctx.drawImage(img, 0, 0, N, N)
        const data = ctx.getImageData(0, 0, N, N).data
        let max = 0
        for (let y = 0; y < N; y++) {
          for (let x = 0; x < N; x++) {
            if (data[(y * N + x) * 4 + 3] > 24) max = Math.max(max, Math.hypot((x + 0.5) * unit - 12, (y + 0.5) * unit - 12))
          }
        }
        return max
      })())
    }
    return cache.get(src)!
  }
  for (const cell of document.querySelectorAll<HTMLElement>('[data-measure]')) {
    const chip = cell.querySelector<HTMLElement>('span.absolute')
    const icon = chip?.querySelector('img')
    const label = cell.closest('div')?.parentElement?.querySelector<HTMLElement>('[data-ratio-label]')
    if (!chip || !icon || !label) continue
    // 只用两者之比，放大格的 transform 会同时作用于分子分母，不影响结果
    const allow = (chip.getBoundingClientRect().width / 2) / (icon.getBoundingClientRect().width / 24)
    const ratio = (await inkRadius(icon.getAttribute('src')!)) / allow
    label.textContent = `${Math.round(ratio * 100)}%`
    if (ratio > 1) label.style.color = '#dc2626'
    else if (ratio > 0.8) label.style.color = '#d97706'
  }
}

buildBoosted().then(() => {
  createApp(App).mount('#app')
  requestAnimationFrame(() => { void measureAll() })
})
