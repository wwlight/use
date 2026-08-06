import { spawnSync } from 'node:child_process';
import { info, warn, error } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { projectRoot } from "../core/paths.js";
import { writeBrewLiteBackup } from "../generate/brew.js";
import { writeScoopLiteBackup } from "../generate/scoop-lite.js";
import { runBrew } from "../pm/brew.js";
export async function runBackupCommand(platform) {
    const root = projectRoot();
    if (platform === 'macos') {
        const manifest = loadManifest('macos');
        const dumpStatus = runBrew(['bundle', 'dump', '--no-vscode', '--no-npm', '--force', `--file=./${manifest.brewfile}`], root);
        if (dumpStatus !== 0)
            return dumpStatus;
        try {
            const { missing, written } = writeBrewLiteBackup(root, manifest);
            info(`Generated lite Brewfile (${written} items): ${manifest.brewfileLite}`);
            if (missing.length > 0) {
                warn(`Not installed from the lite manifest; skipped: ${missing.join(', ')}`);
            }
            return 0;
        }
        catch (err) {
            error(`Failed to generate lite Brewfile: ${err.message}`);
            return 1;
        }
    }
    const manifest = loadManifest('windows');
    const fullRel = manifest.scoopBackup || 'configs/windows/scoop/backup.json';
    const exportStatus = spawnSync(`scoop export > ./${fullRel}`, {
        stdio: 'inherit',
        shell: true,
        cwd: root,
    }).status ?? 1;
    if (exportStatus !== 0)
        return exportStatus;
    try {
        const { missing, written } = writeScoopLiteBackup(root, manifest);
        info(`Generated lite backup (${written} apps): ${manifest.scoopBackupLite}`);
        if (missing.length > 0) {
            warn(`Not installed from the lite manifest; skipped: ${missing.join(', ')}`);
        }
        return 0;
    }
    catch (err) {
        error(`Failed to generate lite backup: ${err.message}`);
        return 1;
    }
}
