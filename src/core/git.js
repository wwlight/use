import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { skip, success, warn } from "./log.js";
import { runWithSpinner } from "./spinner.js";
import { loadManifest } from "./manifest.js";
function normalizeRepoUrl(url) {
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
function needsGithubAccel(repo) {
    return /^https?:\/\/github\.com\//i.test(repo)
        || /^https?:\/\/raw\.githubusercontent\.com\//i.test(repo);
}
/**
 * Fetch/clone order: selected (USE_ACCEL) → other mirrors → official.
 * Matches install.sh / Scoop Get-ScoopMirrorFetchAttempts when a mirror is selected.
 */
export function githubRepoCandidates(repo) {
    if (!needsGithubAccel(repo))
        return [repo];
    const common = loadManifest('common');
    const mirrors = common.githubAccel?.mirrors ?? [];
    if (mirrors.length === 0)
        return [repo];
    const preferredId = process.env.USE_ACCEL || common.githubAccel?.default;
    const preferred = mirrors.find((m) => m.id === preferredId) || mirrors[0];
    const out = [];
    const seen = new Set();
    const push = (url) => {
        if (!seen.has(url)) {
            seen.add(url);
            out.push(url);
        }
    };
    if (preferred)
        push(`${preferred.prefix}${repo}`);
    for (const mirror of mirrors) {
        if (preferred && mirror.id === preferred.id)
            continue;
        push(`${mirror.prefix}${repo}`);
    }
    push(repo);
    return out;
}
// Abort a transfer that stalls under 1 B/s for 15s instead of killing a
// slow-but-working mirror on a fixed wall-clock timer (matches install.sh /
// install.ps1). A 30s hard cap still guards against dead connections.
const GIT_HTTP_LOW_SPEED_LIMIT = '1';
const GIT_HTTP_LOW_SPEED_TIME = '15';
const GIT_HARD_CAP_MS = 30000;

/** Last non-empty stderr line (git's own diagnosis, e.g. "fatal: ..."). */
function lastStderrLine(text) {
    const trimmed = String(text || '').trim();
    if (!trimmed)
        return '';
    const lines = trimmed.split(/\r?\n/);
    return lines[lines.length - 1].trim();
}

/** Async git exec (spinner-friendly; does not block the event loop). Resolves {ok, message, stdout}. */
export function runGitAsync(cwd, args, timeoutMs = GIT_HARD_CAP_MS) {
    return new Promise((resolve) => {
        const child = spawn('git', args, {
            cwd,
            stdio: ['ignore', 'pipe', 'pipe'],
            env: {
                ...process.env,
                GIT_HTTP_LOW_SPEED_LIMIT,
                GIT_HTTP_LOW_SPEED_TIME,
            },
        });
        let stdout = '';
        let stderr = '';
        child.stdout?.on('data', (d) => {
            stdout += d.toString();
        });
        child.stderr?.on('data', (d) => {
            stderr += d.toString();
        });
        const timer = setTimeout(() => {
            child.kill();
            resolve({ ok: false, message: 'timed out', stdout: '' });
        }, timeoutMs);
        child.on('close', (code) => {
            clearTimeout(timer);
            resolve({ ok: code === 0, message: lastStderrLine(stderr), stdout });
        });
        child.on('error', () => {
            clearTimeout(timer);
            resolve({ ok: false, message: 'failed to start git', stdout: '' });
        });
    });
}

function repoHostLabel(url) {
    try {
        const host = new URL(url).host;
        return host || 'remote';
    }
    catch {
        return 'remote';
    }
}

/**
 * Clone into targetDir trying accel mirrors then official, each behind its own
 * spinner. The dir is removed before every attempt: a killed/partial clone must
 * never poison the next candidate (git refuses non-empty destinations).
 */
async function cloneGitRepoWithFallback(repo, targetDir, failPrefix) {
    let lastMessage = '';
    for (const url of githubRepoCandidates(repo)) {
        fs.rmSync(targetDir, { recursive: true, force: true });
        const result = await runWithSpinner(`Cloning ${repoHostLabel(url)} ...`, async () => {
            return runGitAsync(path.dirname(targetDir), ['clone', '--depth=1', url, targetDir]);
        });
        if (result.ok)
            return;
        lastMessage = result.message;
    }
    throw new Error(`${failPrefix}${lastMessage ? ` (${lastMessage})` : ''}`);
}
export function isGitRepo(dir) {
    return fs.existsSync(`${dir}/.git`);
}
export function isSameRemoteRepo(dir, expected) {
    if (!isGitRepo(dir))
        return false;
    const result = spawnSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { encoding: 'utf8' });
    if (result.status !== 0)
        return false;
    return normalizeRepoUrl(result.stdout.trim()) === normalizeRepoUrl(expected);
}
/** Clone into targetDir, trying accel mirrors then official, under a spinner. */
export async function cloneGitRepo(repo, targetDir, name) {
    fs.mkdirSync(path.dirname(targetDir), { recursive: true });
    await cloneGitRepoWithFallback(repo, targetDir, `Failed to clone ${name}`);
    success(`Cloned ${name}`);
}
async function cloneGitRepoPlugin(repo, targetDir, pluginName) {
    await cloneGitRepoWithFallback(repo, targetDir, `Failed to install plugin: ${pluginName}`);
    success(`Installed plugin: ${pluginName}`);
}
function moveDir(src, dest) {
    try {
        fs.renameSync(src, dest);
    }
    catch (err) {
        if (err?.code !== 'EXDEV')
            throw err;
        fs.cpSync(src, dest, { recursive: true });
        fs.rmSync(src, { recursive: true, force: true });
    }
}
/** Clone into a temp dir first; only replace target after a successful clone. */
async function reinstallGitRepoPlugin(repo, targetDir, pluginName) {
    const parent = path.dirname(targetDir);
    fs.mkdirSync(parent, { recursive: true });
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `vpr-plugin-${pluginName}-`));
    const staged = path.join(tempDir, 'repo');
    const backup = path.join(parent, `.${path.basename(targetDir)}.vpr-old-${process.pid}`);
    try {
        await cloneGitRepoPlugin(repo, staged, pluginName);
        fs.rmSync(backup, { recursive: true, force: true });
        fs.renameSync(targetDir, backup);
        try {
            moveDir(staged, targetDir);
        }
        catch (err) {
            fs.renameSync(backup, targetDir);
            throw err;
        }
        fs.rmSync(backup, { recursive: true, force: true });
    }
    finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
}
export async function syncGitRepoPlugin(repo, targetDir, pluginName, update = false) {
    // init (update=false): present -> skip; missing -> install
    if (!update) {
        if (fs.existsSync(targetDir)) {
            skip(`Plugin ${pluginName} already exists; skipping`);
            return;
        }
        await cloneGitRepoPlugin(repo, targetDir, pluginName);
        return;
    }
    // vpr zsh-plugin / clink (update=true): always sync to latest
    if (!fs.existsSync(targetDir)) {
        await cloneGitRepoPlugin(repo, targetDir, pluginName);
        return;
    }
    if (!isGitRepo(targetDir) || !isSameRemoteRepo(targetDir, repo)) {
        warn(`Plugin ${pluginName} is missing a matching git remote; reinstalling...`);
        await reinstallGitRepoPlugin(repo, targetDir, pluginName);
        return;
    }
    await runWithSpinner(`Updating plugin: ${pluginName}...`, async () => {
        let fetched = false;
        let lastMessage = '';
        for (const url of githubRepoCandidates(repo)) {
            spawnSync('git', ['-C', targetDir, 'remote', 'set-url', 'origin', url], { stdio: 'ignore' });
            const result = await runGitAsync(targetDir, ['fetch', '--prune', 'origin']);
            if (result.ok) {
                fetched = true;
                break;
            }
            lastMessage = result.message;
        }
        if (!fetched) {
            throw new Error(`Failed to update plugin: ${pluginName}${lastMessage ? ` (${lastMessage})` : ''}`);
        }
        let branch = spawnSync('git', ['-C', targetDir, 'rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' }).stdout.trim();
        if (branch === 'HEAD') {
            const sym = spawnSync('git', ['-C', targetDir, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD'], { encoding: 'utf8' }).stdout.trim();
            branch = sym.replace(/^origin\//, '');
        }
        if (!branch || !(await runGitAsync(targetDir, ['reset', '--hard', `origin/${branch}`])).ok) {
            throw new Error(`Failed to update plugin: ${pluginName}`);
        }
    });
    success(`Updated plugin: ${pluginName}`);
}
