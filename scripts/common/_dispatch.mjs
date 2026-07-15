#!/usr/bin/env node
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { isPowerShell, resolveScript, runBash, runPwsh, stripArgSeparator } from '../lib/_dispatch.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const TASK_MAP = {
  sync: 'config-sync',
  setup: 'git-setup',
  'zsh-plugin': 'zsh-plugins-install',
}

const task = process.argv[2]
const scriptArgs = stripArgSeparator(process.argv.slice(3))

if (!task || !TASK_MAP[task]) {
  console.error(`用法: node dispatch.mjs <${Object.keys(TASK_MAP).join('|')}> [args...]`)
  process.exit(1)
}

const scriptName = TASK_MAP[task]
const useBash = !isPowerShell()
const scriptPath = resolveScript(__dirname, scriptName)

const result = useBash ? runBash(scriptPath, scriptArgs) : runPwsh(scriptPath, scriptArgs)
process.exit(result.status ?? 1)
