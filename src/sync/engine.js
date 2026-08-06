import fs from 'node:fs';
import path from 'node:path';
import { info, step, warn } from "../core/log.js";
import { pathVarsForWindows } from "../core/manifest.js";
import { expandPath, formatLocalDisplay, formatRepoDisplay, homeDir, projectRoot } from "../core/paths.js";
import { backupFile, copyFileDataOnly } from "./copy.js";
import { cleanupSyncTempFile, parsePairLine, readSyncItems, } from "./pairs.js";
function expandItemLocal(local, platform) {
    if (platform === 'windows') {
        const vars = pathVarsForWindows();
        return expandPath(local, {
            home: homeDir(),
            scoopDir: vars.scoopDir,
            softwareAppsDir: vars.softwareAppsDir,
        });
    }
    return expandPath(local, { home: homeDir() });
}
function loadItemsFromEnvOrManifest(platform, direction) {
    const filtered = process.env.SYNC_FILTERED_PAIRS;
    if (filtered && filtered.length > 0 && fs.existsSync(filtered)) {
        const lines = fs.readFileSync(filtered, 'utf8').split(/\r?\n/).filter(Boolean);
        cleanupSyncTempFile(filtered);
        delete process.env.SYNC_FILTERED_PAIRS;
        return lines.map(parsePairLine);
    }
    return readSyncItems(platform, direction);
}
export async function runConfigSync(opts) {
    const items = opts.items ?? loadItemsFromEnvOrManifest(opts.platform, opts.direction);
    if (items.length === 0) {
        throw new Error('No configuration items to sync');
    }
    const root = projectRoot();
    const home = homeDir();
    const backupRoot = expandPath('~/.backup', { home });
    if (!opts.fromDispatch) {
        step(opts.direction === '1'
            ? `Backing up ${items.length} files to the repository...`
            : `Restoring ${items.length} files locally...`);
    }
    let index = 0;
    for (const item of items) {
        index += 1;
        const localAbs = expandItemLocal(item.local, opts.platform);
        const repoAbs = path.join(root, item.repo);
        const localDisp = formatLocalDisplay(localAbs, home);
        if (opts.direction === '1') {
            await copyFileDataOnly(localAbs, repoAbs);
            info(`[${index}/${items.length}] Backed up ${formatRepoDisplay(item.repo)}`);
            continue;
        }
        if (item.backup) {
            try {
                const bakName = await backupFile(localAbs, backupRoot);
                if (bakName) {
                    info(`[${index}/${items.length}] Backed up ${localDisp} -> ~/.backup/${bakName}`);
                }
            }
            catch (err) {
                warn(`Backup failed for ${localDisp}: ${err.message}`);
            }
        }
        await copyFileDataOnly(repoAbs, localAbs, { encoding: item.encoding });
        info(`[${index}/${items.length}] Restored ${localDisp}`);
    }
    info(opts.direction === '1'
        ? 'Configuration backed up to the repository'
        : 'Configuration restored locally');
}
