/**
 * macOS Homebrew pm: install brew, select/deploy mirror, ensure shell hook.
 */
import fs from 'node:fs';
import path from 'node:path';
import { runCommand, exitStatus } from "../../core/exec.js";
import { canceled, info, skip, step, stepSuccess, success } from "../../core/log.js";
import { formatPmUsage } from "../../core/usage.js";
import { hasMirror, loadManifest, mirrorInstallMode, } from "../../core/manifest.js";
import { projectRoot } from "../../core/paths.js";
import { formatAlignedChoices, runMenuSelect } from "../../lib/menu-select.js";
import { canOpenTerminal } from "../../lib/tty-term.js";
import { brewMirrorConfigFile, brewMirrorEnv, deployBrewRuntime, ensureBrewZprofile, findBrewBinary, } from "./mirror.js";
import { resolveChoiceArg } from "../../core/args.js";
// Bound network-heavy brew steps so a dead mirror fails fast instead of hanging silently.
const BREW_CLONE_TIMEOUT_MS = 30000;
const BREW_INSTALL_TIMEOUT_MS = 300000;
const BREW_UPDATE_TIMEOUT_MS = 300000;
function parseMirrorArg(args) {
    return resolveChoiceArg(args);
}
async function resolveBrewMirror(args) {
    const arg = parseMirrorArg(args);
    if (arg === '__HELP__') {
        console.log(formatPmUsage());
        process.exit(0);
    }
    let mirror = arg;
    if (!mirror && process.env.USE_BREW_MIRROR)
        mirror = process.env.USE_BREW_MIRROR;
    if (mirror) {
        if (!hasMirror(mirror)) {
            console.log(formatPmUsage());
            throw new Error(`Unknown argument: ${args[0] || mirror}`);
        }
        return mirror;
    }
    // curl|bash leaves stdin non-TTY; menu still works via /dev/tty.
    if (!canOpenTerminal({ allowWindowsConsole: true })) {
        throw new Error('Pass an argument in non-interactive environments (example: vpr pm -- ustc)');
    }
    try {
        const mirrors = loadManifest('macos').brewMirrors ?? {};
        const active = process.env.USE_HOMEBREW_MIRROR || '';
        const choice = await runMenuSelect({
            message: 'Choose a Homebrew mirror',
            choices: formatAlignedChoices(Object.entries(mirrors).map(([id, cfg]) => ({
                value: id,
                name: id,
                detail: cfg.label || id,
            })), { activeValue: active }),
            initialValue: active,
        });
        if (!hasMirror(String(choice)))
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
function applySelectedMirror(mirror) {
    const env = brewMirrorEnv(mirror);
    ensureBrewZprofile();
    const display = loadManifest('macos').zprofile || '~/.zprofile';
    success(`Configured Homebrew mirror (${mirror}) in ${display}`);
    return env;
}
function runInstallScript(mirror, env) {
    const macos = loadManifest('macos');
    const cfg = macos.brewMirrors?.[mirror] || {};
    const { mode, url } = mirrorInstallMode(cfg, macos.brewMirrors?.official?.installScript);
    const root = projectRoot();
    const installEnv = { ...env, NONINTERACTIVE: '1' };
    if (mode === 'git') {
        const dest = path.join(root, 'brew-install');
        fs.rmSync(dest, { recursive: true, force: true });
        const clone = runCommand('git', ['clone', '--depth=1', url, dest], { cwd: root, env: installEnv, timeoutMs: BREW_CLONE_TIMEOUT_MS });
        if (exitStatus(clone) !== 0)
            throw new Error('Failed to download the Homebrew installer!');
        const install = runCommand('/bin/bash', [path.join(dest, 'install.sh')], { cwd: root, env: installEnv });
        fs.rmSync(dest, { recursive: true, force: true });
        if (exitStatus(install) !== 0)
            throw new Error('Homebrew installation failed!');
        return;
    }
    const curl = runCommand('/bin/bash', ['-c', `curl -fsSL ${JSON.stringify(url)} | /bin/bash`], {
        cwd: root,
        env: installEnv,
        timeoutMs: BREW_INSTALL_TIMEOUT_MS,
    });
    if (exitStatus(curl) !== 0)
        throw new Error('Homebrew installation failed!');
}
async function installBrew(mirror) {
    await deployBrewRuntime();
    step('Ensuring Homebrew...');
    const env = applySelectedMirror(mirror);
    if (findBrewBinary()) {
        skip('Homebrew is already installed; skipping');
        return;
    }
    info(mirror === 'official'
        ? 'Installing Homebrew from upstream...'
        : `Installing Homebrew from the ${mirror} mirror...`);
    runInstallScript(mirror, env);
    const brew = findBrewBinary();
    if (!brew)
        throw new Error('Homebrew binary not found after install');
    const update = runCommand(brew, ['update'], { env, timeoutMs: BREW_UPDATE_TIMEOUT_MS });
    if (exitStatus(update) !== 0)
        throw new Error('Homebrew update failed!');
    stepSuccess('Homebrew installation complete');
}
function activeBrewMirrorId() {
    if (process.env.USE_HOMEBREW_MIRROR)
        return process.env.USE_HOMEBREW_MIRROR;
    try {
        const config = fs.readFileSync(brewMirrorConfigFile(), 'utf8');
        return config.match(/export USE_HOMEBREW_MIRROR=(\S+)/)?.[1];
    }
    catch {
        return undefined;
    }
}
/** Apply the active mirror env and run the real brew binary. */
export function runBrew(args, cwd = projectRoot()) {
    const brew = findBrewBinary();
    if (!brew)
        throw new Error('brew not found; run vpr pm first');
    const mirrorId = activeBrewMirrorId();
    const env = mirrorId && hasMirror(mirrorId) ? brewMirrorEnv(mirrorId) : process.env;
    return exitStatus(runCommand(brew, args, { cwd, env }));
}
export async function runBrewPmCommand(args = []) {
    const mirror = await resolveBrewMirror(args);
    await installBrew(mirror);
    return 0;
}
