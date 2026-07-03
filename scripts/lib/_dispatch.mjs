import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const scriptsRoot = path.resolve(__dirname, '..')

export function resolveScript(scriptDir, scriptName) {
  const useBash = !isPowerShell()
  const ext = useBash ? '.sh' : '.ps1'
  return path.join(scriptDir, `${scriptName}${ext}`)
}

export function isPowerShell() {
  return Boolean(process.env.PSModulePath)
    || (process.env.ComSpec || '').toLowerCase().includes('pwsh')
}

export function runPwsh(scriptPath, args = []) {
  unblockPowerShellScripts(scriptPath)

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

function unblockPowerShellScripts(scriptPath) {
  const command = [
    '$ErrorActionPreference = "SilentlyContinue"',
    '$scriptsRoot = $env:USE_SCRIPTS_ROOT',
    '$targetScript = $env:USE_TARGET_SCRIPT',
    'if ($scriptsRoot -and (Test-Path -LiteralPath $scriptsRoot)) {',
    '  Get-ChildItem -LiteralPath $scriptsRoot -Recurse -File | Where-Object { $_.Extension -in ".ps1", ".psm1", ".psd1" } | Unblock-File',
    '}',
    'if ($targetScript -and (Test-Path -LiteralPath $targetScript)) {',
    '  Unblock-File -LiteralPath $targetScript',
    '}',
  ].join('; ')
  const options = {
    stdio: 'ignore',
    env: {
      ...process.env,
      USE_SCRIPTS_ROOT: scriptsRoot,
      USE_TARGET_SCRIPT: scriptPath,
    },
  }

  const pwsh = spawnSync('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], options)
  if (pwsh.error && pwsh.error.code === 'ENOENT') {
    spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], options)
  }
}

export function runBash(scriptPath, args = []) {
  return spawnSync('bash', [scriptPath, ...args], {
    stdio: 'inherit',
    shell: false,
  })
}
