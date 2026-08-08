/**
 * Restore installed packages from repository artifacts.
 * Shared by vpr init (any profile) and vpr setup (full).
 */
import fs from 'node:fs';
import path from 'node:path';
import { runPwsh } from "../core/exec.js";
import { resolveProfileArtifact } from "../core/manifest.js";
import { runBrew } from "./brew.js";
export function restoreBrewPackages(root, profile) {
    const brewfile = resolveProfileArtifact('macos', profile);
    const file = path.join(root, brewfile);
    if (!fs.existsSync(file))
        throw new Error(`Brewfile not found: ${file}`);
    const status = runBrew(['bundle', 'install', `--file=${file}`], root);
    if (status !== 0)
        throw new Error('Brewfile dependency installation failed!');
}
export function restoreScoopPackages(root, profile) {
    const status = runPwsh(path.join(root, 'runtime/scoop/import-backup.ps1'), [profile], root);
    if (status !== 0)
        throw new Error('Scoop app restore failed!');
}
