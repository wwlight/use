#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { cleanupSyncTempFile, readSyncPairLines } from './lib/sync-pairs.mjs'
import { writeScoopLiteBackup } from './windows/scoop/lite-backup.mjs'
import { writeBrewLiteBackup } from './macos/brew/generated.mjs'
import {
  SYNC_DIRECTION_EXAMPLE,
  SYNC_DIRECTION_HINT,
  isSyncDirection,
  promptSyncDirectionMenu,
} from './lib/sync-direction.mjs'
import { detectPlatform, isPowerShell, resolveScript, runBash, runPwsh, stripArgSeparator } from './lib/_dispatch.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(__dirname, '..')

const CROSS_PLATFORM_TASKS = ['pm', 'init', 'backup', 'setup', 'sync', 'zsh-plugin', 'git-setup']
const WIN_ONLY_TASKS = ['zsh', 'git-extras', 'clink']
const ALL_TASKS = [...CROSS_PLATFORM_TASKS, ...WIN_ONLY_TASKS]

const task = process.argv[2]
const scriptArgs = stripArgSeparator(process.argv.slice(3))

function exitStatus(result) {
  return result?.status ?? 1
}

function runSubDispatch(relativePath, subTask, args = []) {
  const dispatchPath = path.join(__dirname, relativePath)
  return exitStatus(spawnSync(process.execPath, [dispatchPath, subTask, ...args], { stdio: 'inherit', cwd: projectRoot }))
}

function requirePlatform() {
  const platform = detectPlatform()
  if (!platform) {
    console.error(`[ERROR] Unsupported operating system: ${process.platform}`)
    process.exit(1)
  }
  return platform
}

function requireWindows(platform) {
  if (platform !== 'windows') {
    console.error(`[ERROR] ${task} supports Windows only`)
    process.exit(1)
  }
}

function runPlatformInit(platform) {
  const initDir = path.join(__dirname, platform)
  const scriptPath = resolveScript(initDir, 'init')
  if (process.stdin.isTTY || process.stdout.isTTY) {
    process.env.SYNC_INTERACTIVE = '1'
  }
  const result = isPowerShell() ? runPwsh(scriptPath, scriptArgs) : runBash(scriptPath, scriptArgs)
  return exitStatus(result)
}

function readManifest(scope) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, `${scope}/_manifest.json`), 'utf8'))
}

function runMacBrew(args) {
  return exitStatus(runBash(path.join(__dirname, 'macos/brew/run-brew.sh'), args))
}

function runMacBackup() {
  const manifest = readManifest('macos')
  const dumpStatus = runMacBrew([
    'bundle', 'dump', '--no-vscode', '--no-npm', '--force', `--file=./${manifest.brewfile}`,
  ])
  if (dumpStatus !== 0) return dumpStatus

  try {
    const { missing, written } = writeBrewLiteBackup(projectRoot, manifest)
    console.log(`\x1b[32m[INFO] Generated lite Brewfile (${written} items): ${manifest.brewfileLite}\x1b[0m`)
    if (missing.length > 0) {
      console.warn(`\x1b[33m[WARN] Not installed from the lite manifest; skipped: ${missing.join(', ')}\x1b[0m`)
    }
    return 0
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR] Failed to generate lite Brewfile: ${err.message}\x1b[0m`)
    return 1
  }
}

function runWinBackup() {
  const manifest = readManifest('windows')
  const fullRel = manifest.scoopBackup || 'configs/windows/scoop/backup.json'

  const exportStatus = exitStatus(spawnSync(`scoop export > ./${fullRel}`, { stdio: 'inherit', shell: true, cwd: projectRoot }))
  if (exportStatus !== 0) return exportStatus

  try {
    const { missing, written } = writeScoopLiteBackup(projectRoot, manifest)
    console.log(`\x1b[32m[INFO] Generated lite backup (${written} apps): ${manifest.scoopBackupLite}\x1b[0m`)
    if (missing.length > 0) {
      console.warn(`\x1b[33m[WARN] Not installed from the lite manifest; skipped: ${missing.join(', ')}\x1b[0m`)
    }
    return 0
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR] Failed to generate lite backup: ${err.message}\x1b[0m`)
    return 1
  }
}

function parseSyncDirection(args) {
  const meaningful = args.filter((arg) => arg !== '--')
  if (meaningful.length === 0) return null

  for (const arg of meaningful) {
    if (arg === '1' || arg === '2') return arg
  }

  return '__INVALID__'
}

async function promptSyncDirection(args) {
  const parsed = parseSyncDirection(args)
  if (parsed === '__INVALID__') {
    console.error(`\x1b[31m[ERROR] Invalid sync direction; use 1 or 2\x1b[0m`)
    console.error(SYNC_DIRECTION_EXAMPLE)
    process.exit(1)
  }
  if (parsed) return { direction: parsed }

  try {
    const direction = await promptSyncDirectionMenu()
    if (!isSyncDirection(direction)) {
      console.error(`\x1b[31m[ERROR] Invalid selection: ${direction}\x1b[0m`)
      process.exit(1)
    }
    return { direction }
  }
  catch (err) {
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR] Pass a direction in non-interactive environments: ${SYNC_DIRECTION_HINT}\x1b[0m`)
    console.error(SYNC_DIRECTION_EXAMPLE)
    process.exit(1)
  }
}

function markSyncInteractive() {
  if (process.stdin.isTTY) {
    process.env.SYNC_INTERACTIVE = '1'
  }
}

async function runSyncSelect(direction, lines) {
  if (process.env.SYNC_SELECT_ALL === '1') return null
  if (!process.stdin.isTTY) return null
  if (lines.length === 0) return null

  const filteredFile = path.join(os.tmpdir(), `sync-filtered-${process.pid}.txt`)

  markSyncInteractive()
  try {
    const { runSyncSelectPrompt } = await import('./lib/sync-select.mjs')
    const count = await runSyncSelectPrompt({ direction, rawLines: lines, outPath: filteredFile })
    if (count === 0) {
      cleanupSyncTempFile(filteredFile)
      console.error('\x1b[31m[ERROR] No configuration items to sync\x1b[0m')
      process.exit(1)
    }
    return { file: filteredFile, count }
  }
  catch (err) {
    cleanupSyncTempFile(filteredFile)
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR] ${err?.message || 'File selection canceled'}\x1b[0m`)
    process.exit(1)
  }
}

function logSyncProgress(direction, total) {
  if (total <= 0) return
  const message = direction === '1'
    ? `Backing up ${total} files to the repository...`
    : `Restoring ${total} files locally...`
  console.log(`\x1b[34m[INFO] ${message}\x1b[0m`)
}

async function runUnifiedSync(platform, args) {
  markSyncInteractive()
  process.env.SYNC_FROM_DISPATCH = '1'

  const { direction } = await promptSyncDirection(args)

  let pairLines
  try {
    pairLines = readSyncPairLines(platform, __dirname, direction)
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR] ${err.message}\x1b[0m`)
    process.exit(1)
  }

  const selection = await runSyncSelect(direction, pairLines)

  let tempFile = null
  const itemCount = selection?.count ?? pairLines.length

  if (selection) {
    tempFile = selection.file
    process.env.SYNC_FILTERED_PAIRS = selection.file
  }

  logSyncProgress(direction, itemCount)

  const syncArgs = [direction]

  try {
    return platform === 'macos'
      ? exitStatus(runBash(path.join(__dirname, 'macos/config-sync.sh'), syncArgs))
      : runSubDispatch('windows/_dispatch.mjs', 'sync', syncArgs)
  }
  finally {
    delete process.env.SYNC_FROM_DISPATCH
    delete process.env.SYNC_FILTERED_PAIRS
    cleanupSyncTempFile(tempFile)
  }
}

async function runCrossPlatformTask(platform) {
  switch (task) {
    case 'pm':
      return platform === 'macos'
        ? exitStatus(runBash(path.join(__dirname, 'macos/brew/install.sh'), scriptArgs))
        : runSubDispatch('windows/_dispatch.mjs', 'scoop', scriptArgs)
    case 'init':
      return runPlatformInit(platform)
    case 'backup':
      return platform === 'macos' ? runMacBackup() : runWinBackup()
    case 'setup':
      if (platform === 'macos') {
        const { brewfile } = readManifest('macos')
        return runMacBrew(['bundle', 'install', `--file=./${brewfile}`])
      }
      {
        return runSubDispatch('windows/_dispatch.mjs', 'scoop-import', scriptArgs)
      }
    case 'sync':
      return runUnifiedSync(platform, scriptArgs)
    case 'zsh-plugin':
    case 'git-setup':
      return runSubDispatch('common/_dispatch.mjs', task === 'git-setup' ? 'setup' : task, scriptArgs)
    default:
      return 1
  }
}

function runWinOnlyTask() {
  switch (task) {
    case 'zsh':
    case 'git-extras':
    case 'clink':
      return runSubDispatch('windows/_dispatch.mjs', task, scriptArgs)
    default:
      return 1
  }
}

if (!task || !ALL_TASKS.includes(task)) {
  console.error(`Usage: node _dispatch.mjs <${ALL_TASKS.join('|')}> [args...]`)
  process.exit(1)
}

const platform = requirePlatform()

if (WIN_ONLY_TASKS.includes(task)) {
  requireWindows(platform)
  process.exit(runWinOnlyTask())
}

process.exit(await runCrossPlatformTask(platform))
