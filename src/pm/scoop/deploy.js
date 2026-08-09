/**
 * Deploy runtime/scoop/{scoop.ps1,mirror,services} → ~/.config/scoop/.
 */
import fs from 'node:fs';
import path from 'node:path';
import { loadManifest, pathVarsForWindows } from "../../core/manifest.js";
import { step, stepSuccess, success } from "../../core/log.js";
import { ensureDir, formatLocalDisplay, homeDir, projectRoot, scoopConfigDir } from "../../core/paths.js";
import { copyFileDataOnly } from "../../sync/copy.js";
import { listScoopMirrors } from "./mirror.js";

function writeUtf8NoBom(filePath, content) {
    fs.writeFileSync(filePath, content, 'utf8');
}

export function scoopRuntimeRoot(root = projectRoot()) {
    return path.join(root, 'runtime', 'scoop');
}

export async function deployScoopRuntime(activePrefix = '') {
    const root = projectRoot();
    const win = loadManifest('windows');
    const { scoopDir } = pathVarsForWindows(win);
    const accel = win.scoopAccel;
    if (!accel)
        throw new Error('windows manifest is missing scoopAccel');

    process.env.SCOOP = process.env.SCOOP || scoopDir;
    const configRoot = scoopConfigDir();
    const runtimeRoot = scoopRuntimeRoot(root);
    const mirrors = listScoopMirrors().filter((m) => m.id !== 'official');
    const prefixes = mirrors.map((m) => m.prefix);

    const mirrorDir = path.join(configRoot, 'mirror');
    const libDir = path.join(mirrorDir, 'lib');
    const servicesDir = path.join(configRoot, 'services');
    ensureDir(libDir);
    ensureDir(servicesDir);

    step('Deploying Scoop helpers to ~/.config/scoop ...');

    const payload = {
        mirrorPrefix: prefixes,
        mirrors: mirrors.map(({ id, prefix }) => ({ id, prefix })),
        activePrefix: activePrefix || '',
        githubHosts: accel.githubHosts || [],
        scoopRepo: accel.scoopRepo || 'https://github.com/ScoopInstaller/Scoop',
    };
    writeUtf8NoBom(path.join(mirrorDir, 'state.json'), `${JSON.stringify(payload, null, 2)}\n`);

    const mirrorSrc = path.join(runtimeRoot, 'mirror');
    for (const name of ['hook.ps1', 'shared.ps1']) {
        const src = path.join(mirrorSrc, name);
        if (!fs.existsSync(src))
            throw new Error(`runtime/scoop/mirror/${name} not found: ${src}`);
        await copyFileDataOnly(src, path.join(mirrorDir, name), { encoding: 'utf8Bom' });
        success(`Deployed mirror/${name}`);
    }
    const cliSrc = path.join(mirrorSrc, 'cli.js');
    if (!fs.existsSync(cliSrc))
        throw new Error(`runtime/scoop/mirror/cli.js not found: ${cliSrc}`);
    await copyFileDataOnly(cliSrc, path.join(mirrorDir, 'cli.js'));
    success('Deployed mirror/cli.js');

    for (const name of ['menu-select.js', 'menu-viewport.js', 'string-width.js', 'tty-term.js']) {
        const src = path.join(root, 'src', 'lib', name);
        if (!fs.existsSync(src))
            throw new Error(`Shared menu helper not found: ${src}`);
        await copyFileDataOnly(src, path.join(libDir, name));
    }
    success('Deployed mirror/lib menu helpers');

    const servicesCliSrc = path.join(runtimeRoot, 'services', 'cli.ps1');
    const manifestSrc = path.join(runtimeRoot, 'services', 'manifest.json');
    const scoopPsSrc = path.join(runtimeRoot, 'scoop.ps1');
    if (!fs.existsSync(servicesCliSrc))
        throw new Error(`runtime/scoop/services/cli.ps1 not found: ${servicesCliSrc}`);
    if (!fs.existsSync(scoopPsSrc))
        throw new Error(`runtime/scoop/scoop.ps1 not found: ${scoopPsSrc}`);
    await copyFileDataOnly(servicesCliSrc, path.join(servicesDir, 'cli.ps1'), { encoding: 'utf8Bom' });
    if (fs.existsSync(manifestSrc)) {
        await copyFileDataOnly(manifestSrc, path.join(servicesDir, 'manifest.json'));
    }
    await copyFileDataOnly(scoopPsSrc, path.join(configRoot, 'scoop.ps1'), { encoding: 'utf8Bom' });
    success('Deployed services/ + scoop.ps1');
    stepSuccess(`Deployed Scoop helpers to ${formatLocalDisplay(configRoot, homeDir())}`);
    return { scoopDir, configRoot, prefixes, accel };
}
