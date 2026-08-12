import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildShellCommandLine, exitStatus, runCommand } from "../core/exec.js";
import { cloneGitRepo, runGitAsync, syncGitRepoPlugin } from "../core/git.js";
import { info, skip, step, stepSuccess, success, warn } from "../core/log.js";
import { runWithSpinner } from "../core/spinner.js";
import { loadManifest } from "../core/manifest.js";
import { ensureDir, expandPath, homeDir, projectRoot } from "../core/paths.js";
import { copyFileDataOnly } from "../sync/copy.js";
// Bound network-heavy download so a dead mirror fails fast instead of hanging silently.
const DOWNLOAD_TIMEOUT_MS = 300000;
function commandExists(name) {
    const result = spawnSync(process.platform === 'win32' ? 'where' : 'which', [name], {
        encoding: 'utf8',
        shell: false,
    });
    return result.status === 0 && Boolean((result.stdout || '').trim());
}
function scoopPrefix(app) {
    const result = spawnSync(buildShellCommandLine('scoop', ['prefix', app]), { encoding: 'utf8', shell: true });
    if (result.status !== 0)
        throw new Error(`Could not locate ${app}`);
    const prefix = (result.stdout || '').trim();
    if (!prefix || !fs.existsSync(prefix))
        throw new Error(`Could not locate ${app}`);
    return prefix;
}
function removePathSafe(target) {
    if (!target || !fs.existsSync(target))
        return;
    fs.rmSync(target, { recursive: true, force: true });
}
/** Numeric parts of the first "x.y.z..." run in a tag name (null if none). */
function tagVersionRank(tag) {
    const match = String(tag).match(/\d+(?:\.\d+)*/);
    if (!match)
        return null;
    return match[0].split('.').map((n) => Number(n));
}
function compareRanks(a, b) {
    const len = Math.max(a.length, b.length);
    for (let i = 0; i < len; i++) {
        const va = a[i] ?? 0;
        const vb = b[i] ?? 0;
        if (va !== vb)
            return va - vb;
    }
    return 0;
}
/** Latest tag by numeric version (git's -version:refname sorts "v2.1.0" above "7.5.0", so compare here). */
function selectLatestTag(tags) {
    let best = '';
    let bestRank = null;
    for (const tag of tags) {
        const rank = tagVersionRank(tag);
        if (!rank)
            continue;
        if (!bestRank || compareRanks(rank, bestRank) > 0) {
            best = tag;
            bestRank = rank;
        }
    }
    return best;
}
/** Resolve the newest release tag and leave it checked out (each network op behind its own spinner). */
async function resolveGitExtrasTag(workDir) {
    const ls = await runWithSpinner('Listing remote release tags...', async () => {
        const result = await runGitAsync(workDir, ['ls-remote', '--tags', '--refs', 'origin']);
        if (!result.ok) {
            throw new Error(`Could not list remote tags${result.message ? ` (${result.message})` : ''}`);
        }
        return result;
    });
    const names = (ls.stdout || '')
        .split(/\r?\n/)
        .map((line) => line.split('\t').pop().replace(/^refs\/tags\//, ''))
        .filter(Boolean);
    const tag = selectLatestTag(names);
    if (!tag) {
        throw new Error('Could not resolve the latest tag');
    }
    await runWithSpinner(`Fetching ${tag} ...`, async () => {
        const result = await runGitAsync(workDir, ['fetch', 'origin', tag, '--depth=1']);
        if (!result.ok) {
            throw new Error(`Could not fetch ${tag}${result.message ? ` (${result.message})` : ''}`);
        }
    });
    await runWithSpinner(`Checking out ${tag} ...`, async () => {
        const result = await runGitAsync(workDir, ['checkout', 'FETCH_HEAD']);
        if (!result.ok) {
            throw new Error(`Failed to check out ${tag}${result.message ? ` (${result.message})` : ''}`);
        }
    });
    return tag;
}
export async function runZshInstallCommand(_args = [], options = {}) {
    if (!commandExists('scoop'))
        throw new Error('Scoop is not installed; install Scoop first');
    const manifest = loadManifest('windows');
    const zshInstall = manifest.zshInstall;
    if (!zshInstall)
        throw new Error('windows manifest is missing zshInstall');
    const gitPath = scoopPrefix('git');
    const zshExe = path.join(gitPath, 'usr', 'bin', 'zsh.exe');
    if (fs.existsSync(zshExe)) {
        skip('Zsh is already installed; skipping');
        return 0;
    }
    if (options.header !== false)
        step('Installing Zsh...');
    const workDir = expandPath(zshInstall.workDir || '~/Desktop', { home: homeDir() });
    const tempExtractDir = path.join(workDir, zshInstall.tempExtractDir || 'zsh-temp-extract');
    const cpErrorLog = path.join(workDir, zshInstall.cpErrorLog || 'cp_error.log');
    const zipFile = path.join(workDir, zshInstall.archiveName || 'zsh.pkg.tar.zst');
    const tarFile = zipFile.replace(/\.zst$/, '');
    ensureDir(workDir);
    info('Downloading the Zsh archive...');
    const download = runCommand('curl.exe', ['--ssl-no-revoke', '-L', zshInstall.downloadUrl, '-o', zipFile], { timeoutMs: DOWNLOAD_TIMEOUT_MS });
    if (exitStatus(download) !== 0)
        throw new Error('Failed to download the Zsh archive');
    if (!commandExists('7z')) {
        removePathSafe(zipFile);
        throw new Error('7z command not found; install 7-Zip');
    }
    info('Extracting the Zsh archive...');
    removePathSafe(tempExtractDir);
    ensureDir(tempExtractDir);
    const extractZst = runCommand('7z', ['x', `-o${workDir}`, zipFile]);
    if (exitStatus(extractZst) !== 0) {
        removePathSafe(zipFile);
        removePathSafe(tempExtractDir);
        throw new Error('Failed to extract the .zst file');
    }
    if (!fs.existsSync(tarFile)) {
        removePathSafe(zipFile);
        removePathSafe(tempExtractDir);
        throw new Error('Extracted .tar file not found');
    }
    const extractTar = runCommand('7z', ['x', `-o${tempExtractDir}`, tarFile]);
    if (exitStatus(extractTar) !== 0) {
        removePathSafe(zipFile);
        removePathSafe(tarFile);
        removePathSafe(tempExtractDir);
        throw new Error('Failed to extract the .tar file');
    }
    try {
        for (const entry of fs.readdirSync(tempExtractDir)) {
            const src = path.join(tempExtractDir, entry);
            const dest = path.join(gitPath, entry);
            fs.cpSync(src, dest, { recursive: true, force: true });
        }
        removePathSafe(cpErrorLog);
    }
    catch (err) {
        fs.writeFileSync(cpErrorLog, String(err), 'utf8');
        removePathSafe(zipFile);
        removePathSafe(tarFile);
        removePathSafe(tempExtractDir);
        throw new Error(`Move failed; see details: ${cpErrorLog}`);
    }
    info('Cleaning temporary files...');
    removePathSafe(zipFile);
    removePathSafe(tarFile);
    removePathSafe(tempExtractDir);
    stepSuccess('Zsh installation complete!');
    return 0;
}
export async function runGitExtrasCommand(_args = []) {
    const manifest = loadManifest('windows');
    const repo = manifest.gitExtras?.repo;
    if (!repo)
        throw new Error('windows manifest is missing gitExtras.repo');
    const workDir = path.join(os.tmpdir(), `use-git-extras-${process.pid}-${Date.now()}`);
    step('Installing git-extras...');
    await cloneGitRepo(repo, workDir, 'git-extras');
    // A --depth=1 clone carries no local tag refs, so "rev-list --tags" finds
    // nothing. Resolve the newest tag remotely (one ls-remote), fetch just that
    // one tip (one small fetch), then check out FETCH_HEAD. Ignore git's own
    // -version:refname ordering: it wrongly ranks "v2.1.0" above "7.5.0".
    const latestTag = await resolveGitExtrasTag(workDir);
    info(`Checked out version: ${latestTag}`);
    const gitPath = scoopPrefix('git');
    const installCmd = path.join(workDir, 'install.cmd');
    if (fs.existsSync(installCmd)) {
        const install = runCommand('cmd', ['/c', `install.cmd "${gitPath}"`], { cwd: workDir, shell: true });
        if (exitStatus(install) !== 0) {
            warn('The install command may not have completed successfully; check manually');
        }
    }
    else {
        warn('install.cmd not found');
    }
    info('Verifying installation...');
    const verify = runCommand('git', ['extras', '--help']);
    if (exitStatus(verify) !== 0) {
        throw new Error('git extras command verification failed; installation may be incomplete');
    }
    info('Cleaning temporary files...');
    removePathSafe(workDir);
    stepSuccess('git-extras installation complete!');
    return 0;
}
export async function runClinkCommand(_args = []) {
    const manifest = loadManifest('windows');
    const root = projectRoot();
    step('Configuring Clink...');
    if (!commandExists('scoop'))
        throw new Error('Scoop is not installed; install Scoop first');
    if (!commandExists('clink')) {
        info('Installing Clink through Scoop...');
        const install = runCommand('scoop', ['install', 'clink'], { shell: true });
        if (exitStatus(install) !== 0)
            throw new Error('Clink installation failed');
        success('Clink installed');
    }
    else {
        skip('Clink is already installed; skipping');
    }
    const clinkPath = scoopPrefix('clink');
    const scriptsPath = path.join(clinkPath, 'scripts');
    info('Processing plugins...');
    for (const plugin of manifest.clinkPlugins || []) {
        const targetPath = path.join(scriptsPath, plugin.name);
        await syncGitRepoPlugin(plugin.repo, targetPath, plugin.name, true);
    }
    info('Copying the starship.lua startup plugin...');
    await copyFileDataOnly(path.join(root, 'configs/windows/starship.lua'), path.join(scriptsPath, 'starship.lua'));
    info('Registering Clink scripts...');
    const registerPaths = [
        scriptsPath,
        ...(manifest.clinkPlugins || []).map((p) => path.join(scriptsPath, p.name)),
    ];
    for (const registerPath of registerPaths) {
        const result = runCommand('clink', ['installscripts', registerPath], { shell: true });
        if (exitStatus(result) !== 0)
            warn(`Failed to register ${registerPath}`);
        else
            success(`Registered ${registerPath}`);
    }
    info('Enabling Clink autorun...');
    if (exitStatus(runCommand('clink', ['set', 'tips.enable', 'false'], { shell: true })) !== 0) {
        warn('Failed to set tips.enable');
    }
    if (exitStatus(runCommand('clink', ['autorun', 'install', '--', '--quiet'], { shell: true })) !== 0) {
        warn('Failed to enable Clink autorun');
    }
    else {
        success('Clink autorun enabled');
    }
    stepSuccess('Configuration complete!');
    return 0;
}
