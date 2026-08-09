import path from 'node:path';
import { info, step, stepSuccess } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { projectRoot } from "../core/paths.js";
import { restoreBrewPackages, restoreScoopPackages } from "../pm/restore.js";
/** Restore the full package list from the repository. */
export async function runSetupCommand(platform, _args = []) {
    const root = projectRoot();
    step('Restoring packages (full)...');
    if (platform === 'macos') {
        const { brewfile } = loadManifest('macos');
        if (!brewfile)
            throw new Error('macos manifest is missing brewfile');
        info(`Installing dependencies from ${path.basename(brewfile)}...`);
        restoreBrewPackages(root, 'full');
        stepSuccess('Dependencies installed');
        return 0;
    }
    info('Restoring dependencies from the Scoop backup...');
    await restoreScoopPackages(root, 'full');
    stepSuccess('Dependencies installed');
    return 0;
}
