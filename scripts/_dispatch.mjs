#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import * as readline from 'node:readline/promises'
import { cleanupSyncTempFile, readSyncPairLines } from './lib/sync-pairs.mjs'
import { detectPlatform, isPowerShell, resolveScript, runBash, runPwsh } from './lib/_dispatch.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(__dirname, '..')

const CROSS_PLATFORM_TASKS = ['pm', 'init', 'backup', 'setup', 'sync', 'vite-plus']
const WIN_ONLY_TASKS = ['zsh', 'git-setup', 'git-extras', 'clink', 'hosts']
const ALL_TASKS = [...CROSS_PLATFORM_TASKS, ...WIN_ONLY_TASKS]

const task = process.argv[2]
const scriptArgs = process.argv.slice(3)

function exitStatus(result) {
  return result?.status ?? 1
}

function runSubDispatch(relativePath, subTask, args = []) {
  const dispatchPath = path.join(__dirname, relativePath)
  return exitStatus(spawnSync(process.execPath, [dispatchPath, subTask, ...args], {
    stdio: 'inherit',
    cwd: projectRoot,
  }))
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
  if (platform !== 'win') {
    console.error(`[ERROR] ${task} 仅支持 Windows`)
    process.exit(1)
  }
}

function runMacPm(args) {
  return exitStatus(runBash(path.join(__dirname, 'mac/brew-install.sh'), args))
}

function runPlatformInit(platform) {
  const initDir = path.join(__dirname, platform === 'mac' ? 'mac' : 'windows')
  const scriptPath = resolveScript(initDir, 'init')
  const result = isPowerShell() ? runPwsh(scriptPath, scriptArgs) : runBash(scriptPath, scriptArgs)
  return exitStatus(result)
}

function runMacBackup() {
  return exitStatus(spawnSync('brew', [
    'bundle', 'dump', '--no-vscode', '--no-npm', '--force', '--file=./configs/mac/Brewfile',
  ], { stdio: 'inherit', cwd: projectRoot }))
}

function runMacSetup() {
  return exitStatus(spawnSync('brew', [
    'bundle', 'install', '--file=./configs/mac/Brewfile',
  ], { stdio: 'inherit', cwd: projectRoot }))
}

function runMacSync(args) {
  return runUnifiedSync('mac', args)
}

function runWinBackup() {
  return exitStatus(spawnSync('scoop export > ./configs/windows/scoop_backup.json', {
    stdio: 'inherit',
    shell: true,
    cwd: projectRoot,
  }))
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
    console.error('\x1b[31m[ERROR]\x1b[0m 无效的同步方向: 请使用 1 或 2')
    console.error('示例: vpr sync 2')
    process.exit(1)
  }
  if (parsed) return { direction: parsed, prompted: false }

  if (!process.stdin.isTTY) {
    console.error('\x1b[31m[ERROR]\x1b[0m 非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地')
    console.error('示例: vpr sync 2')
    process.exit(1)
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
  try {
    console.log('请选择拷贝方向:')
    console.log('1) 备份本地配置 -> 仓库')
    console.log('2) 从仓库恢复配置 -> 本地')
    const answer = (await rl.question('> ')).trim()
    if (answer !== '1' && answer !== '2') {
      console.error('\x1b[31m[ERROR]\x1b[0m 无效的同步方向: 请使用 1 或 2')
      console.error('示例: vpr sync 2')
      process.exit(1)
    }
    return { direction: answer, prompted: true }
  }
  finally {
    rl.close()
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
      console.error('\x1b[31m[ERROR]\x1b[0m 没有可同步的配置项')
      process.exit(1)
    }
    return { file: filteredFile, count }
  }
  catch (err) {
    cleanupSyncTempFile(filteredFile)
    if (err?.code === 'CANCELLED') process.exit(130)
    console.error(`\x1b[31m[ERROR]\x1b[0m ${err?.message || '文件选择已取消'}`)
    process.exit(1)
  }
}

function logSyncProgress(direction, total) {
  if (total <= 0) return
  const message = direction === '1'
    ? `正在备份 ${total} 个文件到仓库...`
    : `正在恢复 ${total} 个文件到本地...`
  console.log(`\x1b[32m[INFO]\x1b[0m ${message}`)
}

async function runUnifiedSync(platform, args) {
  markSyncInteractive()
  process.env.SYNC_FROM_DISPATCH = '1'

  let pairLines
  try {
    pairLines = readSyncPairLines(platform, __dirname)
  }
  catch (err) {
    console.error(`\x1b[31m[ERROR]\x1b[0m ${err.message}`)
    process.exit(1)
  }

  const { direction, prompted } = await promptSyncDirection(args)
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
    const status = platform === 'mac'
      ? exitStatus(runBash(path.join(__dirname, 'mac/config-sync.sh'), syncArgs))
      : runSubDispatch('windows/_dispatch.mjs', 'sync', syncArgs)

    if (prompted && status === 0) {
      console.log(`\x1b[32m[INFO]\x1b[0m 下次可直接运行：vpr sync ${direction} 跳过交互选择`)
    }
    return status
  }
  finally {
    delete process.env.SYNC_FROM_DISPATCH
    delete process.env.SYNC_FILTERED_PAIRS
    cleanupSyncTempFile(tempFile)
  }
}

function runWinSetup() {
  return exitStatus(spawnSync('scoop', ['import', './configs/windows/scoop_backup.json'], {
    stdio: 'inherit',
    cwd: projectRoot,
  }))
}

function runWinSync(args) {
  return runUnifiedSync('win', args)
}

async function runCrossPlatformTask(platform) {
  switch (task) {
    case 'pm':
      return platform === 'mac'
        ? runMacPm(scriptArgs)
        : runSubDispatch('windows/_dispatch.mjs', 'scoop', scriptArgs)
    case 'init':
      return runPlatformInit(platform)
    case 'backup':
      return platform === 'mac' ? runMacBackup() : runWinBackup()
    case 'setup':
      return platform === 'mac' ? runMacSetup() : runWinSetup()
    case 'sync':
      return platform === 'mac' ? runMacSync(scriptArgs) : runWinSync(scriptArgs)
    case 'vite-plus':
      return runSubDispatch('common/_dispatch.mjs', 'vite-plus', scriptArgs)
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
    case 'git-setup':
      return runSubDispatch('common/_dispatch.mjs', 'setup', scriptArgs)
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
