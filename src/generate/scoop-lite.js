import fs from 'node:fs';
import path from 'node:path';
function loadGithubAccelPrefixes(projectRoot) {
    const commonPath = path.join(projectRoot, 'manifests/common.json');
    const common = JSON.parse(fs.readFileSync(commonPath, 'utf8'));
    const mirrors = Array.isArray(common.githubAccel?.mirrors) ? common.githubAccel.mirrors : [];
    return mirrors
        .map((item) => String(item?.prefix || '').trim())
        .filter(Boolean)
        .map((prefix) => (prefix.endsWith('/') ? prefix : `${prefix}/`));
}
function stripGithubAccelPrefix(url, prefixes) {
    let value = String(url || '');
    for (const prefix of prefixes) {
        if (value.startsWith(prefix))
            return value.slice(prefix.length);
    }
    return value;
}
/** Keep bucket Sources canonical (official GitHub), not a transient mirror. */
export function normalizeScoopBackupBucketSources(backup, prefixes) {
    const next = structuredClone(backup);
    for (const bucket of next.buckets || []) {
        if (!bucket || bucket.Source == null)
            continue;
        bucket.Source = stripGithubAccelPrefix(bucket.Source, prefixes);
    }
    return next;
}
/**
 * Generate a lite backup from a full Scoop export using manifest.scoopLiteApps.
 */
export function writeScoopLiteBackup(projectRoot, manifest) {
    const fullRel = manifest.scoopBackup;
    const liteRel = manifest.scoopBackupLite;
    const liteNames = manifest.scoopLiteApps;
    if (!fullRel || !liteRel || !Array.isArray(liteNames) || liteNames.length === 0) {
        throw new Error('windows manifest is missing scoopBackup / scoopBackupLite / scoopLiteApps');
    }
    const fullPath = path.join(projectRoot, fullRel);
    const litePath = path.join(projectRoot, liteRel);
    const prefixes = loadGithubAccelPrefixes(projectRoot);
    const full = normalizeScoopBackupBucketSources(JSON.parse(fs.readFileSync(fullPath, 'utf8')), prefixes);
    fs.writeFileSync(fullPath, `${JSON.stringify(full, null, 4)}\n`);
    const byName = new Map((full.apps || []).map((app) => [app.Name, app]));
    const apps = [];
    const missing = [];
    for (const name of liteNames) {
        const app = byName.get(name);
        if (app)
            apps.push(app);
        else
            missing.push(name);
    }
    const bucketNames = new Set(apps.map((app) => app.Source));
    const buckets = (full.buckets || []).filter((b) => bucketNames.has(b.Name));
    fs.writeFileSync(litePath, `${JSON.stringify({ apps, buckets }, null, 4)}\n`);
    return { ok: true, missing, written: apps.length };
}
