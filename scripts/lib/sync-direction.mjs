/**
 * Shared sync-direction text and interactive entry point.
 * CLI: node sync-direction.mjs          -> choose interactively; write 1|2 to stdout
 *      node sync-direction.mjs --hint   -> print the non-interactive hint
 */
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { runMenuSelect } from './menu-select.mjs'

export const SYNC_DIRECTION_MESSAGE = 'Choose a copy direction'

export const SYNC_DIRECTION_CHOICES = [
  { value: '1', label: '1) Back up configuration -> repository' },
  { value: '2', label: '2) Restore configuration -> local machine' },
]

export const SYNC_DIRECTION_HINT = '1=back up config to repository, 2=restore config locally'
export const SYNC_DIRECTION_EXAMPLE = 'Example: vpr sync 2'

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
    throw new Error(`Invalid selection: ${value}`)
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
    console.error(`\x1b[31m[ERROR] ${err?.message || 'Could not select sync direction'}\x1b[0m`)
    process.exit(1)
  }
}
