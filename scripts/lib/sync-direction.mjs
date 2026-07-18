/**
 * 同步方向文案与交互入口（单一来源）。
 * CLI: node sync-direction.mjs          → 交互选择，stdout 输出 1|2
 *      node sync-direction.mjs --hint   → 打印非交互错误提示片段
 */
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { runMenuSelect } from './menu-select.mjs'

export const SYNC_DIRECTION_MESSAGE = '请选择拷贝方向'

export const SYNC_DIRECTION_CHOICES = [
  { value: '1', label: '1) 备份配置 → 仓库' },
  { value: '2', label: '2) 恢复配置 → 本地' },
]

export const SYNC_DIRECTION_HINT = '1=备份配置→仓库, 2=恢复配置→本地'
export const SYNC_DIRECTION_EXAMPLE = '示例: vpr sync 2'

export function isSyncDirection(value) {
  return value === '1' || value === '2'
}

export async function promptSyncDirectionMenu() {
  const direction = await runMenuSelect({
    message: SYNC_DIRECTION_MESSAGE,
    choices: SYNC_DIRECTION_CHOICES,
  })
  const value = String(direction).trim()
  if (!isSyncDirection(value)) {
    throw new Error(`无效选择: ${value}`)
  }
  return value
}

const isCli = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (isCli) {
  if (process.argv[2] === '--hint') {
    process.stdout.write(`${SYNC_DIRECTION_HINT}\n`)
    process.exit(0)
  }

  try {
    const direction = await promptSyncDirectionMenu()
    process.stdout.write(`${direction}\n`)
  }
  catch (err) {
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR] ${err?.message || '无法选择同步方向'}\x1b[0m`)
    process.exit(1)
  }
}
