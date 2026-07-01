#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const TASK_MAP = {
  sync: 'config-sync',
  setup: 'git-setup',
}

function isPowerShell() {
  return Boolean(process.env.PSModulePath)
    || (process.env.ComSpec || '').toLowerCase().includes('pwsh')
}

function runPwsh(scriptPath, args) {
  const pwsh = spawnSync('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], {
    stdio: 'inherit',
  })
  if (pwsh.error && pwsh.error.code === 'ENOENT') {
    return spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], {
      stdio: 'inherit',
    })
  }
  return pwsh
}

function runBash(scriptPath, args) {
  return spawnSync('bash', [scriptPath, ...args], {
    stdio: 'inherit',
    shell: false,
  })
}

const task = process.argv[2]
const scriptArgs = process.argv.slice(3)

if (!task || !TASK_MAP[task]) {
  console.error(`用法: node dispatch.mjs <${Object.keys(TASK_MAP).join('|')}> [args...]`)
  process.exit(1)
}

const scriptName = TASK_MAP[task]
const useBash = !isPowerShell()
const ext = useBash ? '.sh' : '.ps1'
const scriptPath = path.join(__dirname, `${scriptName}${ext}`)

const result = useBash ? runBash(scriptPath, scriptArgs) : runPwsh(scriptPath, scriptArgs)
process.exit(result.status ?? 1)
