// @vitest-environment happy-dom
import { afterEach, expect, it } from 'vitest'
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { formatDateTime } from '../src/runtime/format'
import { i18n } from '../src/runtime/i18n'
import ForwardedMessageCard from '../src/site/components/ForwardedMessageCard.vue'
let wrapper: VueWrapper | undefined
afterEach(() => { wrapper?.unmount(); document.body.innerHTML = '' })
it('opens a bounded snapshot with escaped author/content and resolved stickers', async () => {
  wrapper = mount(ForwardedMessageCard, {
    attachTo: document.body,
    props: {
      bundle: { version: 1, messages: [{ senderName: '<b>Alice</b>', avatarUrl: '/file/img/alice.png', content: '<script>bad()</script> [:sticker:smile:]', createdAt: '2026-09-28T01:00:00Z', msgType: 1 }] },
      stickerUrls: new Map([['smile', '/file/img/smile.png']]),
    }, global: { plugins: [i18n] },
  })
  expect(document.querySelector('[role="dialog"]')).toBeNull()
  await wrapper.get('button').trigger('click')
  await flushPromises()
  const dialog = document.querySelector('[role="dialog"]')!
  expect(dialog).not.toBeNull()
  expect(dialog.querySelector('time')?.textContent).toBe(formatDateTime('2026-09-28T01:00:00Z'))
  expect(dialog.textContent).toContain('<b>Alice</b>')
  expect(dialog.textContent).toContain('<script>bad()</script>')
  expect(dialog.querySelector('script, b, a')).toBeNull()
  expect(dialog.querySelector('img[src="/file/img/alice.png"]')).not.toBeNull()
  expect(dialog.querySelector('img[src="/file/img/smile.png"]')).not.toBeNull()
  ;(dialog.querySelector('button') as HTMLButtonElement).click()
  await flushPromises()
  expect(document.querySelector('[role="dialog"]')).toBeNull()
})
