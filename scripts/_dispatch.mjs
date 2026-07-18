#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { cleanupSyncTempFile, readSyncPairLines } from './lib/sync-pairs.mjs'
import { writeScoopLiteBackup } from './lib/scoop-lite-backup.mjs'
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
const WIN_ONLY_TASKS = ['zsh', 'git-extras', 'clink', 'hosts']
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
    console.error(`[ERROR] 不支持的操作系统: ${process.platform}`)
    process.exit(1)
  }
  return platform
}

function requireWindows(platform) {
  if (platform !== 'windows') {
    console.error(`[ERROR] ${task} 仅支持 windows`)
    process.exit(1)
  }
}

function runPlatformInit(platform) {
  const initDir = path.join(__dirname, platform)
  const scriptPath = resolveScript(initDir, 'init')
  const result = isPowerShell() ? runPwsh(scriptPath, scriptArgs) : runBash(scriptPath, scriptArgs)
  return exitStatus(result)
}

function runMacBackup() {
  return exitStatus(spawnSync('brew', [
    'bundle', 'dump', '--no-vscode', '--no-npm', '--force', '--file=./configs/macos/Brewfile',
  ], { stdio: 'inherit', cwd: projectRoot }))
}

function runWinBackup() {
  const manifestPath = path.join(__dirname, 'windows/_manifest.json')
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  const fullRel = manifest.scoopBackup || 'configs/windows/scoop_backup.json'

  const exportStatus = exitStatus(spawnSync(`scoop export > ./${fullRel}`, { stdio: 'inherit', shell: true, cwd: projectRoot }))
  if (exportStatus !== 0) return exportStatus

  try {
    const { missing, written } = writeScoopLiteBackup(projectRoot, manifest)
    console.log(`\x1b[32m[INFO] 已生成尝鲜版备份（${written} 个应用）: ${manifest.scoopBackupLite}\x1b[0m`)
    if (missing.length > 0) {
      console.warn(`\x1b[33m[WARN] 尝鲜版清单中未安装，已跳过: ${missing.join(', ')}\x1b[0m`)
    }
    return 0
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR] 生成尝鲜版备份失败: ${err.message}\x1b[0m`)
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
    console.error(`\x1b[31m[ERROR] 无效的同步方向: 请使用 1 或 2\x1b[0m`)
    console.error(SYNC_DIRECTION_EXAMPLE)
    process.exit(1)
  }
  if (parsed) return { direction: parsed }

  try {
    const direction = await promptSyncDirectionMenu()
    if (!isSyncDirection(direction)) {
      console.error(`\x1b[31m[ERROR] 无效选择: ${direction}\x1b[0m`)
      process.exit(1)
    }
    return { direction }
  }
  catch (err) {
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR] 非交互环境请传入方向参数: ${SYNC_DIRECTION_HINT}\x1b[0m`)
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
      console.error('\x1b[31m[ERROR] 没有可同步的配置项\x1b[0m')
      process.exit(1)
    }
    return { file: filteredFile, count }
  }
  catch (err) {
    cleanupSyncTempFile(filteredFile)
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR] ${err?.message || '文件选择已取消'}\x1b[0m`)
    process.exit(1)
  }
}

function logSyncProgress(direction, total) {
  if (total <= 0) return
  const message = direction === '1'
    ? `正在备份 ${total} 个文件到仓库...`
    : `正在恢复 ${total} 个文件到本地...`
  console.log(`\x1b[34m[INFO] ${message}\x1b[0m`)
}

async function runUnifiedSync(platform, args) {
  markSyncInteractive()
  process.env.SYNC_FROM_DISPATCH = '1'

  let pairLines
  try {
    pairLines = readSyncPairLines(platform, __dirname)
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR] ${err.message}\x1b[0m`)
    process.exit(1)
  }

  const { direction } = await promptSyncDirection(args)
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
        ? exitStatus(runBash(path.join(__dirname, 'macos/brew-install.sh'), scriptArgs))
        : runSubDispatch('windows/_dispatch.mjs', 'scoop', scriptArgs)
    case 'init':
      return runPlatformInit(platform)
    case 'backup':
      return platform === 'macos' ? runMacBackup() : runWinBackup()
    case 'setup':
      return platform === 'macos'
        ? exitStatus(spawnSync('brew', [
            'bundle', 'install', '--file=./configs/macos/Brewfile',
          ], { stdio: 'inherit', cwd: projectRoot }))
        : exitStatus(spawnSync('scoop', [
            'import', './configs/windows/scoop_backup.json',
          ], { stdio: 'inherit', cwd: projectRoot, shell: true }))
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
    case 'hosts':
    case 'clink':
      return runSubDispatch('windows/_dispatch.mjs', task, scriptArgs)
    default:
      return 1
  }
}

if (!task || !ALL_TASKS.includes(task)) {
  console.error(`用法: node _dispatch.mjs <${ALL_TASKS.join('|')}> [args...]`)
  process.exit(1)
}

const platform = requirePlatform()

if (WIN_ONLY_TASKS.includes(task)) {
  requireWindows(platform)
  process.exit(runWinOnlyTask())
}

process.exit(await runCrossPlatformTask(platform))
