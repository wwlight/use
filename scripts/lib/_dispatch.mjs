import { spawnSync } from 'node:child_process'
import path from 'node:path'

export function detectPlatform() {
  const p = process.platform
  if (p === 'darwin') return 'macos'
  if (p === 'win32') return 'windows'
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

/** Strip npm/vpr `--` arg separators (e.g. `vpr pm -- ustc`). */
export function stripArgSeparator(args = []) {
  return args.filter((arg) => arg !== '--')
}

export function runPwsh(scriptPath, args = []) {
  // -ExecutionPolicy Bypass is already set; recursive Unblock-File adds several seconds.
  const cleanArgs = stripArgSeparator(args)

  const pwsh = spawnSync('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...cleanArgs], {
    stdio: 'inherit',
  })
  if (pwsh.error && pwsh.error.code === 'ENOENT') {
    return spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...cleanArgs], {
      stdio: 'inherit',
    })
  }
  return pwsh
}

export function runBash(scriptPath, args = []) {
  return spawnSync('bash', [scriptPath, ...stripArgSeparator(args)], {
    stdio: 'inherit',
    shell: true,
  })
}
