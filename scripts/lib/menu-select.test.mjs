import assert from 'node:assert/strict'
import { parseChoice } from './menu-select.mjs'
import { isSyncDirection, SYNC_DIRECTION_CHOICES, SYNC_DIRECTION_HINT } from './sync-direction.mjs'

assert.deepEqual(parseChoice('lite) 尝鲜版'), { value: 'lite', label: 'lite) 尝鲜版' })
assert.deepEqual(parseChoice('1) 备份配置 → 仓库'), { value: '1', label: '1) 备份配置 → 仓库' })
assert.throws(() => parseChoice('nocolon'), /选项格式/)

assert.equal(isSyncDirection('1'), true)
assert.equal(isSyncDirection('2'), true)
assert.equal(isSyncDirection('3'), false)
assert.equal(isSyncDirection('lite'), false)

assert.equal(SYNC_DIRECTION_CHOICES.length, 2)
assert.ok(SYNC_DIRECTION_HINT.includes('备份配置'))
assert.ok(SYNC_DIRECTION_HINT.includes('恢复配置'))

console.log('menu-select.test.mjs: ok')
