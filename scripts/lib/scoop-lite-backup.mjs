import fs from 'node:fs'
import path from 'node:path'

/**
 * 从完整 scoop export 按 manifest.scoopLiteApps 生成尝鲜版备份。
 * @returns {{ ok: boolean, missing: string[], written: number }}
 */
export function writeScoopLiteBackup(projectRoot, manifest) {
  const fullRel = manifest.scoopBackup
  const liteRel = manifest.scoopBackupLite
  const liteNames = manifest.scoopLiteApps

  if (!fullRel || !liteRel || !Array.isArray(liteNames) || liteNames.length === 0) {
    throw new Error('windows manifest 缺少 scoopBackup / scoopBackupLite / scoopLiteApps')
  }

  const fullPath = path.join(projectRoot, fullRel)
  const litePath = path.join(projectRoot, liteRel)
  const full = JSON.parse(fs.readFileSync(fullPath, 'utf8'))
  const byName = new Map((full.apps || []).map((app) => [app.Name, app]))

  const apps = []
  const missing = []
  for (const name of liteNames) {
    const app = byName.get(name)
    if (app) apps.push(app)
    else missing.push(name)
  }

  const bucketNames = new Set(apps.map((app) => app.Source))
  const buckets = (full.buckets || []).filter((b) => bucketNames.has(b.Name))

  fs.writeFileSync(litePath, `${JSON.stringify({ apps, buckets }, null, 4)}\n`)
  return { ok: true, missing, written: apps.length }
}
