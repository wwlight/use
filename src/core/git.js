import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { info, warn } from "./log.js";
import { loadManifest } from "./manifest.js";
export function normalizeRepoUrl(url) {
    let u = url.trim();
    const common = loadManifest('common');
    for (const mirror of common.githubAccel?.mirrors ?? []) {
        if (u.startsWith(mirror.prefix)) {
            u = u.slice(mirror.prefix.length);
            break;
        }
    }
    while (u.endsWith('/'))
        u = u.slice(0, -1);
    if (u.endsWith('.git'))
        u = u.slice(0, -4);
    u = u.replace(/^https?:\/\//, '').replace(/^ssh:\/\/git@/, '').replace(/^git@/, '');
    u = u.replace(/:/g, '/');
    return u;
}
export function githubAccelUrl(repo) {
    const common = loadManifest('common');
    const mirrors = common.githubAccel?.mirrors ?? [];
    const preferred = process.env.USE_ACCEL
        || common.githubAccel?.default;
    const mirror = mirrors.find((m) => m.id === preferred) || mirrors[0];
    if (!mirror)
        return repo;
    if (/^https?:\/\/github\.com\//i.test(repo) || /^https?:\/\/raw\.githubusercontent\.com\//i.test(repo)) {
        return `${mirror.prefix}${repo}`;
    }
    return repo;
}
export function githubRepoCandidates(repo) {
    const out = [repo];
    const accel = githubAccelUrl(repo);
    if (accel !== repo)
        out.unshift(accel);
    return out;
}
function runGit(cwd, args) {
    const result = spawnSync('git', args, { cwd, stdio: 'ignore' });
    return result.status === 0;
}
export function isSameRemoteRepo(dir, expected) {
    if (!fs.existsSync(`${dir}/.git`))
        return false;
    const result = spawnSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { encoding: 'utf8' });
    if (result.status !== 0)
        return false;
    return normalizeRepoUrl(result.stdout.trim()) === normalizeRepoUrl(expected);
}
export function syncGitRepoPlugin(repo, targetDir, pluginName, update = false) {
    if (!fs.existsSync(targetDir)) {
        info(`Downloading plugin: ${pluginName}...`);
        for (const url of githubRepoCandidates(repo)) {
            const result = spawnSync('git', ['clone', '--depth=1', url, targetDir], { stdio: 'ignore' });
            if (result.status === 0) {
                info(`Installed plugin: ${pluginName}`);
                return;
            }
        }
        throw new Error(`Failed to install plugin: ${pluginName}`);
    }
    if (!update) {
        info(`Plugin ${pluginName} already exists; skipping`);
        return;
    }
    if (!isSameRemoteRepo(targetDir, repo)) {
        warn(`Plugin ${pluginName} exists but remote does not match; skipping update`);
        return;
    }
    info(`Plugin ${pluginName} is linked to the remote repository; updating...`);
    const accel = githubAccelUrl(repo);
    spawnSync('git', ['-C', targetDir, 'remote', 'set-url', 'origin', accel], { stdio: 'ignore' });
    if (!runGit(targetDir, ['fetch', '--prune', 'origin'])) {
        throw new Error(`Failed to update plugin: ${pluginName}`);
    }
    let branch = spawnSync('git', ['-C', targetDir, 'rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' }).stdout.trim();
    if (branch === 'HEAD') {
        const sym = spawnSync('git', ['-C', targetDir, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD'], { encoding: 'utf8' }).stdout.trim();
        branch = sym.replace(/^origin\//, '');
    }
    if (!branch || !runGit(targetDir, ['reset', '--hard', `origin/${branch}`])) {
        throw new Error(`Failed to update plugin: ${pluginName}`);
    }
    info(`Updated plugin: ${pluginName}`);
}
