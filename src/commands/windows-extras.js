import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { exitStatus, runCommand } from "../core/exec.js";
import { githubRepoCandidates, syncGitRepoPlugin } from "../core/git.js";
import { info, step, warn } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { ensureDir, expandPath, homeDir, projectRoot } from "../core/paths.js";
import { copyFileDataOnly } from "../sync/copy.js";
function commandExists(name) {
    const result = spawnSync(process.platform === 'win32' ? 'where' : 'which', [name], {
        encoding: 'utf8',
        shell: false,
    });
    return result.status === 0 && Boolean((result.stdout || '').trim());
}
function scoopPrefix(app) {
    const result = spawnSync('scoop', ['prefix', app], { encoding: 'utf8', shell: true });
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
function cloneGitRepo(repo, targetPath, name) {
    ensureDir(path.dirname(targetPath));
    removePathSafe(targetPath);
    info(`Cloning ${name}...`);
    for (const url of githubRepoCandidates(repo)) {
        const result = runCommand('git', ['clone', '--depth=1', url, targetPath]);
        if (exitStatus(result) === 0) {
            info(`Cloned ${name}`);
            return;
        }
    }
    throw new Error(`Failed to clone ${name}`);
}
export async function runZshInstallCommand(_args = []) {
    if (!commandExists('scoop'))
        throw new Error('Scoop is not installed; install Scoop first');
    const manifest = loadManifest('windows');
    const zshInstall = manifest.zshInstall;
    if (!zshInstall)
        throw new Error('windows manifest is missing zshInstall');
    const gitPath = scoopPrefix('git');
    const zshExe = path.join(gitPath, 'usr', 'bin', 'zsh.exe');
    if (fs.existsSync(zshExe)) {
        info('Zsh is already installed; skipping');
        return 0;
    }
    const workDir = expandPath(zshInstall.workDir || '~/Desktop', { home: homeDir() });
    const tempExtractDir = path.join(workDir, zshInstall.tempExtractDir || 'zsh-temp-extract');
    const cpErrorLog = path.join(workDir, zshInstall.cpErrorLog || 'cp_error.log');
    const zipFile = path.join(workDir, zshInstall.archiveName || 'zsh.pkg.tar.zst');
    const tarFile = zipFile.replace(/\.zst$/, '');
    ensureDir(workDir);
    step('Step 1/6: Downloading the Zsh archive...');
    const download = runCommand('curl.exe', ['--ssl-no-revoke', '-L', zshInstall.downloadUrl, '-o', zipFile]);
    if (exitStatus(download) !== 0)
        throw new Error('Failed to download the Zsh archive');
    info(`Download complete: ${zipFile}`);
    step('Step 2/6: Locating the Git installation...');
    info(`Git path: ${gitPath}`);
    step('Step 3/6: Checking the 7z tool...');
    if (!commandExists('7z')) {
        removePathSafe(zipFile);
        throw new Error('7z command not found; install 7-Zip');
    }
    info('7z is available');
    step('Step 4/6: Extracting the .zst file...');
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
    info('.zst extraction complete');
    step('Step 5/6: Extracting the .tar file and moving files...');
    const extractTar = runCommand('7z', ['x', `-o${tempExtractDir}`, tarFile]);
    if (exitStatus(extractTar) !== 0) {
        removePathSafe(zipFile);
        removePathSafe(tarFile);
        removePathSafe(tempExtractDir);
        throw new Error('Failed to extract the .tar file');
    }
    info('.tar extraction complete');
    try {
        for (const entry of fs.readdirSync(tempExtractDir)) {
            const src = path.join(tempExtractDir, entry);
            const dest = path.join(gitPath, entry);
            fs.cpSync(src, dest, { recursive: true, force: true });
        }
        info('Files moved');
        removePathSafe(cpErrorLog);
    }
    catch (err) {
        fs.writeFileSync(cpErrorLog, String(err), 'utf8');
        removePathSafe(zipFile);
        removePathSafe(tarFile);
        removePathSafe(tempExtractDir);
        throw new Error(`Move failed; see details: ${cpErrorLog}`);
    }
    step('Step 6/6: Cleaning temporary files...');
    removePathSafe(zipFile);
    removePathSafe(tarFile);
    removePathSafe(tempExtractDir);
    info('Zsh installation complete!');
    return 0;
}
export async function runGitExtrasCommand(_args = []) {
    const manifest = loadManifest('windows');
    const repo = manifest.gitExtras?.repo;
    if (!repo)
        throw new Error('windows manifest is missing gitExtras.repo');
    const workDir = path.join(os.tmpdir(), `use-git-extras-${process.pid}-${Date.now()}`);
    step('Step 1/5: Cloning the git-extras repository to a temporary directory...');
    cloneGitRepo(repo, workDir, 'git-extras');
    if (!fs.existsSync(path.join(workDir, '.git'))) {
        throw new Error('Failed to clone the git-extras repository');
    }
    step('Step 2/5: Entering the git-extras directory...');
    step('Step 3/5: Checking out the latest version...');
    const latestCommit = spawnSync('git', ['rev-list', '--tags', '--max-count=1'], {
        cwd: workDir,
        encoding: 'utf8',
    });
    if (latestCommit.status !== 0 || !latestCommit.stdout.trim()) {
        throw new Error('Could not resolve the latest tag commit');
    }
    const latestTag = spawnSync('git', ['describe', '--tags', latestCommit.stdout.trim()], {
        cwd: workDir,
        encoding: 'utf8',
    });
    if (latestTag.status !== 0 || !latestTag.stdout.trim()) {
        throw new Error('Could not resolve the latest tag');
    }
    const checkout = runCommand('git', ['checkout', latestTag.stdout.trim()], { cwd: workDir });
    if (exitStatus(checkout) !== 0)
        throw new Error('Failed to check out the latest tag');
    info(`Checked out version: ${latestTag.stdout.trim()}`);
    step('Step 4/5: Installing git-extras...');
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
    step('Step 5/5: Verifying installation...');
    const verify = runCommand('git', ['extras', '--help']);
    if (exitStatus(verify) !== 0) {
        throw new Error('git extras command verification failed; installation may be incomplete');
    }
    info('Installation verified');
    info('Cleaning temporary files...');
    removePathSafe(workDir);
    info('git-extras installation complete!');
    return 0;
}
export async function runClinkCommand(_args = []) {
    const manifest = loadManifest('windows');
    const root = projectRoot();
    step('Step 1/4: Checking Scoop installation...');
    if (!commandExists('scoop'))
        throw new Error('Scoop is not installed; install Scoop first');
    info('Scoop is installed');
    step('Step 2/4: Checking Clink installation...');
    if (!commandExists('clink')) {
        warn('Clink is not installed; installing through Scoop...');
        const install = runCommand('scoop', ['install', 'clink'], { shell: true });
        if (exitStatus(install) !== 0)
            throw new Error('Clink installation failed');
        info('Clink installation complete');
    }
    else {
        info('Clink is already installed; skipping');
    }
    const clinkPath = scoopPrefix('clink');
    const scriptsPath = path.join(clinkPath, 'scripts');
    info('Clink installation path:');
    console.log(clinkPath);
    step('Step 3/4: Processing plugins...');
    for (const plugin of manifest.clinkPlugins || []) {
        const targetPath = path.join(scriptsPath, plugin.name);
        syncGitRepoPlugin(plugin.repo, targetPath, plugin.name, true);
    }
    info('Copying the starship.lua startup plugin...');
    await copyFileDataOnly(path.join(root, 'configs/windows/starship.lua'), path.join(scriptsPath, 'starship.lua'));
    info('Registering Clink scripts...');
    const registerPaths = [
        scriptsPath,
        ...(manifest.clinkPlugins || []).map((p) => path.join(scriptsPath, p.name)),
    ];
    for (const registerPath of registerPaths) {
        info(`Registering: ${registerPath}`);
        const result = runCommand('clink', ['installscripts', registerPath], { shell: true });
        if (exitStatus(result) !== 0)
            warn(`Failed to register ${registerPath}`);
        else
            info(`Registered ${registerPath}`);
    }
    step('Step 4/4: Enabling Clink autorun...');
    if (exitStatus(runCommand('clink', ['set', 'tips.enable', 'false'], { shell: true })) !== 0) {
        warn('Failed to set tips.enable');
    }
    if (exitStatus(runCommand('clink', ['autorun', 'install', '--', '--quiet'], { shell: true })) !== 0) {
        warn('Failed to enable Clink autorun');
    }
    else {
        info('Clink autorun enabled');
    }
    info('Configuration complete!');
    return 0;
}
