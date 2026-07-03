import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

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
