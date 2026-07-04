import fs from 'node:fs'
import path from 'node:path'

export function readSyncPairLines(platform, scriptsDir) {
  const scopes = platform === 'mac' ? ['mac', 'common'] : ['windows', 'common']
  const lines = []

  for (const scope of scopes) {
    const manifestPath = path.join(scriptsDir, scope, '_manifest.json')
    if (!fs.existsSync(manifestPath)) {
      throw new Error(`找不到 manifest: ${manifestPath}`)
    }
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
    for (const item of manifest.sync?.toRepo ?? []) {
      lines.push(`${item.local}\t${item.repo}\t${item.backup ? '1' : '0'}`)
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
    // 文件可能已被 shell 侧消费并删除
  }
}
