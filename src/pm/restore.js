/**
 * Restore installed packages from repository artifacts.
 * Shared by vpr init (any profile) and vpr setup (full).
 */
import fs from 'node:fs';
import path from 'node:path';
import { resolveProfileArtifact } from "../core/manifest.js";
import { runBrew } from "./brew/index.js";
import { restoreScoopPackages } from "./scoop/import.js";

export function restoreBrewPackages(root, profile) {
    const brewfile = resolveProfileArtifact('macos', profile);
    const file = path.join(root, brewfile);
    if (!fs.existsSync(file))
        throw new Error(`Brewfile not found: ${file}`);
    const status = runBrew(['bundle', 'install', `--file=${file}`], root);
    if (status !== 0)
        throw new Error('Brewfile dependency installation failed!');
}

export { restoreScoopPackages };
