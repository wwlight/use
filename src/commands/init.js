import fs from 'node:fs';
import path from 'node:path';
import { info, step } from "../core/log.js";
import { formatInitUsage, hasProfile, loadManifest, profileLabel, resolveProfileArtifact, } from "../core/manifest.js";
import { ensureManifestDirectories } from "../core/dirs.js";
import { markCliInteractive } from "../core/platform.js";
import { projectRoot } from "../core/paths.js";
import { runPwsh } from "../core/exec.js";
import { formatAlignedChoices, runMenuSelect } from "../lib/menu-select.js";
import { canOpenTerminal } from "../lib/tty-term.js";
import { runBrew } from "../pm/brew.js";
import { runGitSetupCommand } from "./git-setup.js";
import { runZshInstallCommand } from "./windows-extras.js";
import { runZshPluginCommand } from "./zsh-plugin.js";
import { runConfigSync } from "../sync/engine.js";
function parseProfileArg(args) {
    const clean = args.filter((a) => a !== '--');
    if (clean[0] === '-h' || clean[0] === '--help' || clean[0] === 'help')
        return '__HELP__';
    let value = clean[0] || '';
    if (value.startsWith('--'))
        value = value.slice(2);
    return value;
}
async function resolveProfile(args, platform) {
    const arg = parseProfileArg(args);
    if (arg === '__HELP__') {
        console.log(formatInitUsage());
        process.exit(0);
    }
    if (arg) {
        if (!hasProfile(arg)) {
            console.log(formatInitUsage());
            throw new Error(`Unknown argument: ${args[0]}`);
        }
        return arg;
    }
    // curl|bash leaves stdin non-TTY; menu still works via /dev/tty.
    if (!canOpenTerminal({ allowWindowsConsole: true })) {
        throw new Error('Pass an argument in non-interactive environments (example: vpr init -- lite)');
    }
    const message = platform === 'macos'
        ? 'Choose the Homebrew installation profile'
        : 'Choose the Scoop installation profile';
    try {
        const profiles = loadManifest('common').profiles ?? {};
        const choice = await runMenuSelect({
            message,
            choices: formatAlignedChoices(Object.entries(profiles).map(([id, cfg]) => ({
                value: id,
                name: id,
                detail: cfg.label || id,
            }))),
        });
        if (!hasProfile(String(choice)))
            throw new Error(`Invalid selection: ${choice}`);
        return String(choice);
    }
    catch (err) {
        if (err?.code === 'CANCELLED') {
            console.error('Canceled');
            process.exit(130);
        }
        throw err;
    }
}
function nextStep(current, total, message) {
    current.n += 1;
    step(`Step ${current.n}/${total}: ${message}`);
}
async function restorePackages(platform, profile) {
    const label = profileLabel(profile);
    const root = projectRoot();
    if (platform === 'macos') {
        const brewfile = resolveProfileArtifact('macos', profile);
        const file = path.join(root, brewfile);
        if (!fs.existsSync(file))
            throw new Error(`Brewfile not found: ${file}`);
        info(`Restoring Homebrew dependencies (${label})...`);
        info(`Installing dependencies from ${path.basename(file)}...`);
        const status = runBrew(['bundle', 'install', `--file=${file}`], root);
        if (status !== 0)
            throw new Error('Brewfile dependency installation failed!');
        info('Brewfile dependencies installed');
        return;
    }
    info(`Installing/restoring Scoop apps (${label})...`);
    const status = runPwsh(path.join(root, 'runtime/scoop/import-backup.ps1'), [profile], root);
    if (status !== 0)
        throw new Error('Scoop app restore failed!');
}
export async function runInitCommand(platform, args) {
    markCliInteractive();
    const profile = await resolveProfile(args, platform);
    const total = 4;
    const current = { n: 0 };
    const root = projectRoot();
    nextStep(current, total, 'Creating directory structure...');
    ensureManifestDirectories(platform);
    nextStep(current, total, `Restoring packages (${profileLabel(profile)})...`);
    await restorePackages(platform, profile);
    nextStep(current, total, platform === 'windows' ? 'Installing Zsh and plugins...' : 'Installing Zsh plugins...');
    if (platform === 'windows') {
        await runZshInstallCommand([]);
    }
    await runZshPluginCommand([], { update: false });
    nextStep(current, total, 'Syncing configuration...');
    process.env.SYNC_PROFILE = profile;
    process.env.SYNC_SELECT_ALL = '1';
    try {
        await runConfigSync({ platform, direction: '2', fromDispatch: true });
    }
    finally {
        delete process.env.SYNC_SELECT_ALL;
    }
    await runGitSetupCommand([]);
    info('All operations complete. The system is ready.');
    return 0;
}
