import path from 'node:path';
import { canceled, info, step, success } from "../core/log.js";
import { hasProfile, loadManifest, profileLabel, resolveProfileArtifact, } from "../core/manifest.js";
import { formatInitUsage } from "../core/usage.js";
import { ensureManifestDirectories } from "../core/dirs.js";
import { markCliInteractive } from "../core/platform.js";
import { projectRoot } from "../core/paths.js";
import { formatAlignedChoices, runMenuSelect } from "../lib/menu-select.js";
import { canOpenTerminal } from "../lib/tty-term.js";
import { restoreBrewPackages, restoreScoopPackages } from "../pm/restore.js";
import { runGitSetupCommand } from "./git-setup.js";
import { runZshInstallCommand } from "./windows-extras.js";
import { runZshPluginCommand } from "./zsh-plugin.js";
import { runConfigSync } from "../sync/engine.js";
import { resolveChoiceArg } from "../core/args.js";
function parseProfileArg(args) {
    return resolveChoiceArg(args);
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
            if (!err.printed)
                canceled();
            process.exit(130);
        }
        throw err;
    }
}
async function restorePackages(platform, profile) {
    const root = projectRoot();
    if (platform === 'macos') {
        const brewfile = resolveProfileArtifact('macos', profile);
        info(`Installing dependencies from ${path.basename(brewfile)}...`);
        restoreBrewPackages(root, profile);
        success('Brewfile dependencies installed');
        return;
    }
    info('Restoring dependencies from the Scoop backup...');
    await restoreScoopPackages(root, profile);
    success('Scoop packages restored');
}
export async function runInitCommand(platform, args) {
    markCliInteractive();
    const profile = await resolveProfile(args, platform);
    const root = projectRoot();
    step('Creating directory structure...');
    ensureManifestDirectories(platform);
    success('Directory structure ready');
    step(`Restoring packages (${profileLabel(profile)})...`);
    await restorePackages(platform, profile);
    step(platform === 'windows' ? 'Installing Zsh and plugins...' : 'Installing Zsh plugins...');
    if (platform === 'windows') {
        await runZshInstallCommand([], { header: false });
    }
    await runZshPluginCommand([], { update: false, header: false });
    step('Syncing configuration...');
    process.env.SYNC_PROFILE = profile;
    process.env.SYNC_SELECT_ALL = '1';
    try {
        await runConfigSync({ platform, direction: '2', fromDispatch: true });
    }
    finally {
        delete process.env.SYNC_SELECT_ALL;
    }
    await runGitSetupCommand([]);
    // One-click install prints its own finale; standalone init keeps this line.
    if (process.env.USE_INSTALLER !== '1') {
        process.stderr.write('\n');
        success('All operations complete. The system is ready.');
    }
    return 0;
}
