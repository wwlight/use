import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { step, stepSuccess, warn, error } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { projectRoot } from "../core/paths.js";
import { runBrew } from "../pm/brew.js";
const BREW_DIRECTIVE = /^\s*(tap|brew|cask|mas|vscode|whalebrew)\s+"([^"]+)"/;
function atomicWrite(filePath, content) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    const temp = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(temp, content, { encoding: 'utf8', mode: 0o644 });
    fs.renameSync(temp, filePath);
}
function parseBrewfile(content) {
    const records = [];
    let pending = [];
    for (const line of content.split(/\r?\n/)) {
        const match = line.match(BREW_DIRECTIVE);
        if (match) {
            records.push({
                type: match[1],
                name: match[2],
                lines: [...pending, line],
            });
            pending = [];
        }
        else if (!line.trim() || line.trimStart().startsWith('#')) {
            pending.push(line);
        }
        else {
            pending = [];
        }
    }
    return records;
}
function cleanField(value, field) {
    const text = String(value ?? '').trim();
    if (/[\t\r\n]/.test(text))
        throw new Error(`${field} contains a tab or newline`);
    return text;
}
function liteKeys(manifest) {
    if (!Array.isArray(manifest.brewLiteItems) || manifest.brewLiteItems.length === 0) {
        throw new Error('macos manifest brewLiteItems must not be empty');
    }
    const keys = [];
    const seen = new Set();
    for (const item of manifest.brewLiteItems) {
        const type = cleanField(item?.type, 'brewLiteItems.type');
        const name = cleanField(item?.name, 'brewLiteItems.name');
        if (!type || !name)
            throw new Error('brewLiteItems entries require type and name');
        const key = `${type}:${name}`;
        if (seen.has(key))
            throw new Error(`Duplicate brewLiteItems entry: ${key}`);
        seen.add(key);
        keys.push(key);
    }
    return keys;
}
function requiredTap(name) {
    const parts = name.split('/');
    return parts.length >= 3 ? `${parts[0]}/${parts[1]}` : '';
}
export function renderBrewLite(fullContent, manifest) {
    const records = parseBrewfile(fullContent);
    const byKey = new Map(records.map((record) => [`${record.type}:${record.name}`, record]));
    const selectedKeys = liteKeys(manifest);
    const missing = selectedKeys.filter((key) => !byKey.has(key));
    const selected = new Set(selectedKeys);
    for (const key of selectedKeys) {
        const record = byKey.get(key);
        if (!record)
            continue;
        const tap = requiredTap(record.name);
        if (tap && byKey.has(`tap:${tap}`))
            selected.add(`tap:${tap}`);
    }
    const lines = ['# Generated from Brewfile using manifests/macos.json brewLiteItems.'];
    for (const record of records) {
        if (!selected.has(`${record.type}:${record.name}`))
            continue;
        while (lines.length > 1 && lines.at(-1) === '' && record.lines[0] === '')
            lines.pop();
        lines.push(...record.lines);
    }
    while (lines.at(-1) === '')
        lines.pop();
    return { content: `${lines.join('\n')}\n`, missing, written: selectedKeys.length - missing.length };
}
function writeBrewLiteBackup(root, manifest) {
    if (!manifest.brewfile || !manifest.brewfileLite) {
        throw new Error('macos manifest is missing brewfile / brewfileLite');
    }
    const fullPath = path.join(root, manifest.brewfile);
    const litePath = path.join(root, manifest.brewfileLite);
    const result = renderBrewLite(fs.readFileSync(fullPath, 'utf8'), manifest);
    atomicWrite(litePath, result.content);
    return result;
}
function loadGithubAccelPrefixes(root) {
    const commonPath = path.join(root, 'manifests/common.json');
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
function normalizeScoopBackupBucketSources(backup, prefixes) {
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
function writeScoopLiteBackup(root, manifest) {
    const fullRel = manifest.scoopBackup;
    const liteRel = manifest.scoopBackupLite;
    const liteNames = manifest.scoopLiteApps;
    if (!fullRel || !liteRel || !Array.isArray(liteNames) || liteNames.length === 0) {
        throw new Error('windows manifest is missing scoopBackup / scoopBackupLite / scoopLiteApps');
    }
    const fullPath = path.join(root, fullRel);
    const litePath = path.join(root, liteRel);
    const prefixes = loadGithubAccelPrefixes(root);
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
export async function runBackupCommand(platform) {
    const root = projectRoot();
    step('Backing up installed packages...');
    if (platform === 'macos') {
        const manifest = loadManifest('macos');
        const dumpStatus = runBrew(['bundle', 'dump', '--no-vscode', '--no-npm', '--force', `--file=./${manifest.brewfile}`], root);
        if (dumpStatus !== 0)
            return dumpStatus;
        try {
            const { missing, written } = writeBrewLiteBackup(root, manifest);
            stepSuccess(`Generated lite Brewfile (${written} items): ${manifest.brewfileLite}`);
            if (missing.length > 0) {
                warn(`Not installed from the lite manifest; skipped: ${missing.join(', ')}`);
            }
            return 0;
        }
        catch (err) {
            error(`Failed to generate lite Brewfile: ${err.message}`);
            return 1;
        }
    }
    const manifest = loadManifest('windows');
    const fullRel = manifest.scoopBackup || 'configs/windows/scoop/backup.json';
    const exportStatus = spawnSync(`scoop export > ./${fullRel}`, {
        stdio: 'inherit',
        shell: true,
        cwd: root,
    }).status ?? 1;
    if (exportStatus !== 0)
        return exportStatus;
    try {
        const { missing, written } = writeScoopLiteBackup(root, manifest);
        stepSuccess(`Generated lite backup (${written} apps): ${manifest.scoopBackupLite}`);
        if (missing.length > 0) {
            warn(`Not installed from the lite manifest; skipped: ${missing.join(', ')}`);
        }
        return 0;
    }
    catch (err) {
        error(`Failed to generate lite backup: ${err.message}`);
        return 1;
    }
}
