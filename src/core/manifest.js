import fs from 'node:fs';
import path from 'node:path';
import { projectRoot, resolveScoopDir, resolveSoftwareAppsDir, scoopConfigDir } from "./paths.js";
const cache = new Map();
export function manifestsDir() {
    return path.join(projectRoot(), 'manifests');
}
export function loadManifest(scope) {
    const cached = cache.get(scope);
    if (cached)
        return cached;
    const file = path.join(manifestsDir(), `${scope}.json`);
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    cache.set(scope, data);
    return data;
}
export function clearManifestCache() {
    cache.clear();
}
export function syncScopes(platform) {
    return platform === 'macos' ? ['macos', 'common'] : ['windows', 'common'];
}
export function pathVarsForWindows(win = loadManifest('windows')) {
    const scoopDir = resolveScoopDir(win.scoopDir);
    const softwareAppsDir = resolveSoftwareAppsDir(win.softwareAppsDir, scoopDir);
    return { scoopDir, softwareAppsDir, scoopConfigDir: scoopConfigDir() };
}
export function hasProfile(name, common = loadManifest('common')) {
    return Boolean(common.profiles?.[name]);
}
export function profileLabel(name, common = loadManifest('common')) {
    const label = common.profiles?.[name]?.label;
    if (!label)
        throw new Error(`Unknown profile: ${name}`);
    return label;
}
export function hasMirror(name, macos = loadManifest('macos')) {
    return Boolean(macos.brewMirrors?.[name]);
}
export function resolveProfileArtifact(scope, profile) {
    const m = loadManifest(scope);
    const artifactKey = m.profileArtifacts?.[profile];
    if (!artifactKey)
        throw new Error(`${scope} is missing profileArtifacts.${profile}`);
    const rel = m[artifactKey];
    if (typeof rel !== 'string' || !rel)
        throw new Error(`${scope} is missing field: ${artifactKey}`);
    return rel;
}
export function zshPluginsDir(common = loadManifest('common')) {
    if (!common.zshPluginsDir)
        throw new Error('common manifest is missing zshPluginsDir');
    return common.zshPluginsDir;
}
export function mirrorInstallMode(cfg, officialScript) {
    if (cfg?.installGitRepo)
        return { mode: 'git', url: cfg.installGitRepo };
    const url = cfg?.installScript || officialScript;
    if (!url)
        throw new Error('installScript / installGitRepo missing');
    return { mode: 'script', url };
}
