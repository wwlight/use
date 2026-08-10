/**
 * Windows Scoop pm: Node orchestration + PowerShell bootstrap for OS-heavy steps.
 */
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import { runPwsh } from "../../core/exec.js";
import { info, step, stepSuccess, warn } from "../../core/log.js";
import { loadManifest, pathVarsForWindows } from "../../core/manifest.js";
import { ensureDir, projectRoot } from "../../core/paths.js";
import { deployScoopRuntime } from "./deploy.js";
import { formatScoopMirrorLabel, resolveScoopMirror } from "./mirror.js";

function bootstrapScript() {
    return path.join(projectRoot(), 'runtime', 'scoop', 'bootstrap', 'entry.ps1');
}

function readBootstrapPrefix(outFile, fallback) {
    if (!fs.existsSync(outFile))
        return fallback;
    try {
        const text = fs.readFileSync(outFile, 'utf8');
        const m = text.match(/^USE_SCOOP_ACTIVE_PREFIX=(.*)$/m);
        return m ? m[1].trim() : fallback;
    }
    catch {
        return fallback;
    }
}

function runBootstrap(phase, activePrefix, root) {
    const outFile = path.join(os.tmpdir(), `use-scoop-bootstrap-${process.pid}.txt`);
    const prev = process.env.USE_SCOOP_BOOTSTRAP_OUT;
    try {
        process.env.USE_SCOOP_BOOTSTRAP_OUT = outFile;
        const code = runPwsh(bootstrapScript(), [
            '-ActivePrefix', activePrefix ?? '',
            '-Phase', phase,
        ], root);
        if (code === 130)
            process.exit(130);
        if (code !== 0)
            throw new Error(`Scoop bootstrap (${phase}) failed with exit ${code}`);
        return readBootstrapPrefix(outFile, activePrefix);
    }
    finally {
        if (prev === undefined)
            delete process.env.USE_SCOOP_BOOTSTRAP_OUT;
        else
            process.env.USE_SCOOP_BOOTSTRAP_OUT = prev;
        if (fs.existsSync(outFile))
            fs.unlinkSync(outFile);
    }
}

export async function runScoopPmCommand(args = []) {
    if (process.platform !== 'win32') {
        throw new Error('Scoop pm supports Windows only');
    }

    const root = projectRoot();
    const win = loadManifest('windows');
    const { scoopDir, softwareAppsDir } = pathVarsForWindows(win);
    ensureDir(softwareAppsDir);
    process.env.SCOOP = process.env.SCOOP || scoopDir;

    let activePrefix = await resolveScoopMirror(args);
    const selectedLabel = formatScoopMirrorLabel(activePrefix);
    const quiet = process.env.USE_QUIET_INSTALL === '1' || process.env.USE_QUIET_PM === '1';

    if (!quiet) {
        info(`Selected mirror: ${activePrefix || 'Upstream'}`);
    }

    const run = async () => {
        const afterInstall = runBootstrap('install', activePrefix, root);
        if (afterInstall !== activePrefix) {
            warn(
                `Selected mirror was ${selectedLabel}; `
                + `active mirror is ${formatScoopMirrorLabel(afterInstall)} after install fallback`,
            );
            activePrefix = afterInstall;
        }
        await deployScoopRuntime(activePrefix);
        activePrefix = runBootstrap('finish', activePrefix, root);
    };

    if (quiet) {
        step('Configuring Scoop mirror');
        stepSuccess(`Setting up Scoop (${selectedLabel}) ...`);
    }
    await run();
    return 0;
}

export { restoreScoopPackages } from "./import.js";
export { deployScoopRuntime } from "./deploy.js";
