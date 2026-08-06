import fs from 'node:fs';
import path from 'node:path';
import { info } from "../core/log.js";
import { loadManifest, resolveProfileArtifact } from "../core/manifest.js";
import { projectRoot } from "../core/paths.js";
import { runPwsh } from "../core/exec.js";
import { runBrew } from "../pm/brew.js";
/** Restore the full package list from the repository. */
export async function runSetupCommand(platform, _args = []) {
    const root = projectRoot();
    if (platform === 'macos') {
        const { brewfile } = loadManifest('macos');
        if (!brewfile)
            throw new Error('macos manifest is missing brewfile');
        const file = path.join(root, brewfile);
        if (!fs.existsSync(file))
            throw new Error(`Brewfile not found: ${file}`);
        info(`Installing dependencies from ${path.basename(file)}...`);
        return runBrew(['bundle', 'install', `--file=./${brewfile}`], root);
    }
    const artifact = resolveProfileArtifact('windows', 'full');
    const backup = path.join(root, artifact);
    if (!fs.existsSync(backup))
        throw new Error(`Scoop backup file not found: ${backup}`);
    info(`Restoring dependencies from ${path.basename(backup)}...`);
    return runPwsh(path.join(root, 'runtime/scoop/import-backup.ps1'), ['full'], root);
}
