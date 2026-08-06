import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
function findRepoRoot(startDir) {
    let dir = path.resolve(startDir);
    for (;;) {
        if (fs.existsSync(path.join(dir, 'manifests', 'common.json')))
            return dir;
        const parent = path.dirname(dir);
        if (parent === dir)
            return null;
        dir = parent;
    }
}
export function projectRoot() {
    return findRepoRoot(__dirname) || path.resolve(__dirname, '../..');
}
export function homeDir() {
    return process.env.USERPROFILE || process.env.HOME || os.homedir();
}
export function resolveScoopDir(manifestScoopDir) {
    const fromEnv = process.env.USE_SCOOP_DIR || process.env.SCOOP;
    if (fromEnv && fromEnv.trim())
        return path.resolve(fromEnv.trim());
    if (manifestScoopDir && manifestScoopDir.trim())
        return path.resolve(manifestScoopDir.trim());
    return path.resolve('D:\\SoftwareApps\\Scoop');
}
export function resolveSoftwareAppsDir(manifestDir, scoopDir) {
    if (process.env.USE_SOFTWARE_APPS_DIR?.trim()) {
        return path.resolve(process.env.USE_SOFTWARE_APPS_DIR.trim());
    }
    if (manifestDir?.trim())
        return path.resolve(manifestDir.trim());
    if (scoopDir)
        return path.dirname(scoopDir);
    return path.resolve('D:/SoftwareApps');
}
/** Expand ~ and {scoopDir}/{softwareAppsDir} placeholders. */
export function expandPath(input, vars = {}) {
    const home = vars.home ?? homeDir();
    let p = input.replace(/\\/g, '/');
    if (vars.scoopDir) {
        const scoop = vars.scoopDir.replace(/\\/g, '/');
        p = p.replaceAll('{scoopDir}', scoop);
    }
    if (vars.softwareAppsDir) {
        const apps = vars.softwareAppsDir.replace(/\\/g, '/');
        p = p.replaceAll('{softwareAppsDir}', apps);
    }
    if (p === '~')
        return home;
    if (p.startsWith('~/'))
        return path.join(home, p.slice(2));
    if (process.platform === 'win32') {
        return path.normalize(p.replace(/\//g, path.sep));
    }
    return path.normalize(p);
}
export function formatRepoDisplay(repo) {
    return repo.startsWith('./') ? repo : `./${repo}`;
}
export function formatLocalDisplay(localPath, home = homeDir()) {
    const normalized = localPath.replace(/\\/g, '/');
    const homeNorm = home.replace(/\\/g, '/').replace(/\/$/, '');
    if (normalized === homeNorm)
        return '~';
    if (normalized.startsWith(`${homeNorm}/`)) {
        return `~/${normalized.slice(homeNorm.length + 1)}`;
    }
    return normalized;
}
export function ensureDir(dir) {
    fs.mkdirSync(dir, { recursive: true });
}
