import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { formatAlignedChoices, parseChoice } from './menu-select.mjs'
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
assert.match(aligned[0].label, /^  npm -+ https:\/\/registry\.npmjs\.org\/$/)
assert.match(aligned[1].label, /^\* jd -+ http:\/\/registry\.m\.jd\.com\/$/)
assert.match(aligned[2].label, /^  official -+ https:\/\/github\.com\/$/)
// Mark column: * or space always at index 0
assert.equal(aligned[0].label[0], ' ')
assert.equal(aligned[1].label[0], '*')
assert.equal(aligned[2].label[0], ' ')
// Name column starts at index 2 for every row
assert.equal(aligned[0].label.indexOf('npm'), 2)
assert.equal(aligned[1].label.indexOf('jd'), 2)
assert.equal(aligned[2].label.indexOf('official'), 2)
// Dashes absorb name-length differences so URLs align
assert.ok(aligned[1].label.match(/-+/)[0].length > aligned[2].label.match(/-+/)[0].length)
assert.equal(aligned[0].label.indexOf('http'), aligned[1].label.indexOf('http'))
assert.equal(aligned[1].label.indexOf('http'), aligned[2].label.indexOf('http'))

// Cursor pad: ✓ is typically 2 terminal columns in CJK locales; empty pointer is 2 spaces.
const menuSource = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'menu-select.mjs'), 'utf8')
assert.match(menuSource, /function cursorPointer/)
assert.match(menuSource, /active \? '✓' : ' {2}'/)

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

console.log('menu-select.test.mjs: ok')
