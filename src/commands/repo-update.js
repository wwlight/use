/**
 * `vpr repo-update` — update an existing checkout of this repository in place.
 *
 * The installers keep the initial fetch (no repo yet -> no CLI to run), but
 * delegate the update/heal path here so the mirror-fallback + reset logic is
 * shared with git.js instead of being re-implemented in install.sh / install.ps1.
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { success, warn } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { githubRepoCandidates, runGitAsync, stripGithubAccelPrefix } from "../core/git.js";
import { runWithSpinner } from "../core/spinner.js";

export function repoUrl() {
    const common = loadManifest('common');
    const url = String(common.repo || '').trim();
    if (!url)
        throw new Error('common manifest is missing repo');
    return url;
}

/** Convert a zip checkout (no .git) into a git repo tracking the canonical origin. */
function convertToGitRepo(targetDir) {
    if (fs.existsSync(path.join(targetDir, '.git')))
        return true;
    const init = spawnSync('git', ['-C', targetDir, 'init'], { stdio: 'ignore' });
    if (init.status !== 0)
        return false;
    const remote = spawnSync('git', ['-C', targetDir, 'remote', 'add', 'origin', repoUrl()], { stdio: 'ignore' });
    if (remote.status !== 0)
        return false;
    return true;
}

/** Fetch origin/main via accel mirrors then official, under a spinner. */
async function fetchOriginMain(targetDir) {
    const origin = spawnSync('git', ['-C', targetDir, 'remote', 'get-url', 'origin'], { encoding: 'utf8' }).stdout.trim();
    const base = origin || stripGithubAccelPrefix(repoUrl());
    let lastMessage = '';
    for (const url of githubRepoCandidates(base)) {
        spawnSync('git', ['-C', targetDir, 'remote', 'set-url', 'origin', url], { stdio: 'ignore' });
        const result = await runWithSpinner(`Syncing ${safeHost(url)} ...`, async () => {
            return runGitAsync(targetDir, ['fetch', '--prune', 'origin', 'main']);
        });
        if (result.ok)
            return true;
        lastMessage = result.message;
    }
    warn(lastMessage ? `Sync failed: ${lastMessage}` : 'Sync failed');
    return false;
}

function safeHost(url) {
    try {
        return new URL(url).host || 'remote';
    }
    catch {
        return 'remote';
    }
}

/**
 * Update the checkout at `targetDir` (default: project root) to origin/main.
 * Returns 0 on success. Non-git (zip) checkouts are healed into git first.
 */
export async function runRepoUpdateCommand(targetDir = process.cwd()) {
    const abs = path.resolve(targetDir);
    if (!fs.existsSync(abs))
        throw new Error(`Checkout not found: ${abs}`);
    if (!convertToGitRepo(abs)) {
        throw new Error(`Failed to convert ${abs} to a git checkout`);
    }
    if (!(await fetchOriginMain(abs))) {
        throw new Error('Failed to fetch remote repository');
    }
    const reset = await runGitAsync(abs, ['reset', '--hard', 'origin/main']);
    if (!reset.ok) {
        throw new Error(`Failed to reset local repository: ${reset.message || ''}`);
    }
    success('Repository synced with origin/main');
    return 0;
}