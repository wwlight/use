import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { formatAlignedChoices, formatChoiceLine, parseChoice } from './menu-select.mjs'
import { formatSyncChoiceLine } from './sync-select.mjs'
import { alignMenuCheck, MENU_CHECK, stringWidth } from './string-width.mjs'
import { isSyncDirection, SYNC_DIRECTION_CHOICES, SYNC_DIRECTION_HINT } from './sync-direction.mjs'

assert.deepEqual(parseChoice('lite) 尝鲜版'), { value: 'lite', label: '尝鲜版' })
assert.deepEqual(parseChoice('1) 备份配置 → 仓库'), { value: '1', label: '备份配置 → 仓库' })
assert.deepEqual(parseChoice('ustc) * ustc ---------- https://example/'), {
  value: 'ustc',
  label: '* ustc ---------- https://example/',
})
// Inactive mark is a space — must not be trimStart'd away (keeps * column aligned).
assert.deepEqual(parseChoice('tuna)   tuna ---------- https://example/'), {
  value: 'tuna',
  label: '  tuna ---------- https://example/',
})
assert.throws(() => parseChoice('nocolon'), /Expected option format/)

const aligned = formatAlignedChoices([
  { value: 'npm', name: 'npm', detail: 'https://registry.npmjs.org/' },
  { value: 'jd', name: 'jd', detail: 'http://registry.m.jd.com/' },
  { value: 'official', name: 'official', detail: 'https://github.com/' },
], { activeValue: 'jd' })
assert.equal(aligned[0].value, 'npm')
assert.equal(aligned[1].value, 'jd')
assert.match(aligned[0].label, /^  npm\s+-{10} https:\/\/registry\.npmjs\.org\/$/)
assert.match(aligned[1].label, /^\* jd\s+-{10} http:\/\/registry\.m\.jd\.com\/$/)
assert.match(aligned[2].label, /^  official -{10} https:\/\/github\.com\/$/)
// Mark column: * or space always at index 0
assert.equal(aligned[0].label[0], ' ')
assert.equal(aligned[1].label[0], '*')
assert.equal(aligned[2].label[0], ' ')
// Name column starts at index 2 for every row
assert.equal(aligned[0].label.indexOf('npm'), 2)
assert.equal(aligned[1].label.indexOf('jd'), 2)
assert.equal(aligned[2].label.indexOf('official'), 2)
// Fixed dash column + space-padded names → dashes and URLs share columns
assert.equal(aligned[0].label.match(/-+/)[0].length, aligned[2].label.match(/-+/)[0].length)
assert.equal(aligned[0].label.indexOf('-'), aligned[1].label.indexOf('-'))
assert.equal(aligned[1].label.indexOf('-'), aligned[2].label.indexOf('-'))
assert.equal(aligned[0].label.indexOf('http'), aligned[1].label.indexOf('http'))
assert.equal(aligned[1].label.indexOf('http'), aligned[2].label.indexOf('http'))

const menuSource = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'menu-select.mjs'), 'utf8')
const syncSource = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'sync-select.mjs'), 'utf8')
const widthSource = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'string-width.mjs'), 'utf8')
assert.match(menuSource, /formatChoiceLine/)
assert.match(menuSource, /alignMenuCheck/)
assert.match(syncSource, /alignMenuCheck/)
assert.match(widthSource, /export function alignMenuCheck/)
assert.equal(MENU_CHECK, '✓')
assert.ok(!menuSource.includes("POINTER_ACTIVE = '❯'"))
assert.ok(!menuSource.includes('function cursorPointer'))
assert.ok(!syncSource.includes("POINTER_ACTIVE = '>'"))

assert.equal(isSyncDirection('1'), true)
assert.equal(isSyncDirection('2'), true)
assert.equal(isSyncDirection('3'), false)
assert.equal(isSyncDirection('lite'), false)

assert.equal(SYNC_DIRECTION_CHOICES.length, 2)
assert.ok(SYNC_DIRECTION_HINT.includes('back up config'))
assert.ok(SYNC_DIRECTION_HINT.includes('restore config'))

assert.match(menuSource, /\\x1B\[J/)
assert.match(menuSource, /One write/)
assert.ok(!menuSource.includes('clearPreviousFrame'))

assert.equal(alignMenuCheck(true), '✓')
assert.equal(alignMenuCheck(false), ' ')

// Single-select (scoop/brew mirror, sync direction, init menus)
assert.equal(formatChoiceLine('label', true), '✓ label')
assert.equal(formatChoiceLine('label', false), '  label')
const narrow = { ambiguousWide: false }
assert.equal(
  stringWidth(formatChoiceLine('label', true).slice(0, 2), narrow),
  stringWidth(formatChoiceLine('label', false).slice(0, 2), narrow),
)

// Multi-select (vpr sync file picker): only the leading ✓ cursor is width-fixed
assert.equal(formatSyncChoiceLine('a.txt', { selected: true, active: false }), '  [✓] a.txt')
assert.equal(formatSyncChoiceLine('b.txt', { selected: false, active: true }), '✓ [ ] b.txt')
assert.equal(formatSyncChoiceLine('c.txt', { selected: true, active: true }), '✓ [✓] c.txt')
const syncActive = formatSyncChoiceLine('x', { active: true })
const syncIdle = formatSyncChoiceLine('x', { active: false })
assert.equal(syncActive.indexOf('['), syncIdle.indexOf('['))
assert.match(syncSource, /alignMenuCheck\(active\)/)
assert.ok(!syncSource.includes('alignMenuCheck(selected)'))
assert.match(syncSource, /allowWindowsConsole:\s*true/)

const syncDirectionSource = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'sync-direction.mjs'), 'utf8')
assert.match(syncDirectionSource, /MENU_SELECT_OUT/)

console.log('menu-select.test.mjs: ok')
