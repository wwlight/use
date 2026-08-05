import fs from 'node:fs'
import path from 'node:path'

export function readSyncPairLines(platform, scriptsDir, direction) {
  const scopes = platform === 'macos' ? ['macos', 'common'] : ['windows', 'common']
  const lines = []

  for (const scope of scopes) {
    const manifestPath = path.join(scriptsDir, scope, '_manifest.json')
    if (!fs.existsSync(manifestPath)) {
      throw new Error(`Manifest not found: ${manifestPath}`)
    }
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
    for (const item of manifest.sync?.toRepo ?? []) {
      if (direction === '1' && item.restoreOnly === true) continue
      lines.push(`${item.local}\t${item.repo}\t${item.backup ? '1' : '0'}\t${item.encoding ?? ''}\t${item.defaultSelected === false ? '0' : '1'}`)
    }
  }

  return lines
}

export function formatRepoDisplay(repo) {
  return repo.startsWith('./') ? repo : `./${repo}`
}

export function formatLocalDisplay(localPath) {
  const normalized = localPath.replace(/\\/g, '/')
  const home = (process.env.USERPROFILE || process.env.HOME || '').replace(/\\/g, '/').replace(/\/$/, '')
  if (home) {
    if (normalized === home) return '~'
    if (normalized.startsWith(`${home}/`)) return `~/${normalized.slice(home.length + 1)}`
  }

  return normalized
}

export function cleanupSyncTempFile(filePath) {
  if (!filePath) return
  try {
    fs.unlinkSync(filePath)
  }
  catch {
    // The shell may already have consumed and removed the file.
  }
}
