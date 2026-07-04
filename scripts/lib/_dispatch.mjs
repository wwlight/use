import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

export function detectPlatform() {
  const p = process.platform
  if (p === 'darwin') return 'mac'
  if (p === 'win32') return 'win'
  return null
}

export function resolveScript(scriptDir, scriptName) {
  const useBash = !isPowerShell()
  const ext = useBash ? '.sh' : '.ps1'
  return path.join(scriptDir, `${scriptName}${ext}`)
}

export function isPowerShell() {
  return Boolean(process.env.PSModulePath)
    || (process.env.ComSpec || '').toLowerCase().includes('pwsh')
}

export function unblockPowerShellScripts() {
  const command = `Get-ChildItem -LiteralPath '${scriptsDir.replace(/'/g, "''")}' -Recurse -Include *.ps1,*.psm1 | Unblock-File -ErrorAction SilentlyContinue`
  const options = { stdio: 'ignore' }
  const pwsh = spawnSync('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], options)
  if (pwsh.error?.code === 'ENOENT') {
    spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], options)
  }
}

export function runPwsh(scriptPath, args = []) {
  unblockPowerShellScripts()

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

export function runBash(scriptPath, args = []) {
  return spawnSync('bash', [scriptPath, ...args], {
    stdio: 'inherit',
    shell: false,
  })
}
