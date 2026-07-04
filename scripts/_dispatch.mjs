#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { detectPlatform, isPowerShell, resolveScript, runBash, runPwsh, unblockPowerShellScripts } from './lib/_dispatch.mjs'

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
  for (const arg of args) {
    if (arg === '1' || arg === '2') return arg
  }
  return null
}

function captureScript(scriptPath, args = []) {
  if (isPowerShell()) {
    unblockPowerShellScripts()
  }
  return spawnSync(
    isPowerShell() ? 'pwsh' : 'bash',
    isPowerShell()
      ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args]
      : [scriptPath, ...args],
    { cwd: projectRoot, encoding: 'utf8', stdio: ['inherit', 'pipe', 'inherit'] },
  )
}

function resolveSyncDirection(args) {
  const parsed = parseSyncDirection(args)
  if (parsed) return { direction: parsed, prompted: false }

  const scriptPath = resolveScript(path.join(__dirname, 'common'), 'prompt-sync-direction')
  const result = captureScript(scriptPath, [])
  if (result.status !== 0) process.exit(result.status ?? 1)

  const direction = result.stdout.trim()
  if (direction !== '1' && direction !== '2') {
    console.error('[ERROR] 无效的同步方向')
    process.exit(1)
  }
  return { direction, prompted: true }
}

function runUnifiedSync(platform, args) {
  const { direction, prompted } = resolveSyncDirection(args)
  const syncArgs = [direction]

  const status = platform === 'mac'
    ? exitStatus(runBash(path.join(__dirname, 'mac/config-sync.sh'), syncArgs))
    : runSubDispatch('windows/_dispatch.mjs', 'sync', syncArgs)

  if (prompted && status === 0) {
    console.log(`\x1b[32m[INFO]\x1b[0m 下次可直接运行：vpr sync ${direction} 跳过交互选择`)
  }
  return status
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

function runCrossPlatformTask(platform) {
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

process.exit(runCrossPlatformTask(platform))
