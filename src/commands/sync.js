import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { canceled, error, step, warn } from "../core/log.js";
import { markCliInteractive } from "../core/platform.js";
import { isHelpFlag, stripDashArgs } from "../core/args.js";
import { formatSyncUsage } from "../core/usage.js";
import { SYNC_DIRECTION_EXAMPLE, SYNC_DIRECTION_HINT, isSyncDirection, normalizeSyncDirection, promptSyncDirectionMenu, } from "../sync/direction.js";
import { runConfigSync } from "../sync/engine.js";
import { cleanupSyncTempFile, readSyncPairLines } from "../sync/pairs.js";
import { runSyncSelectPrompt } from "../sync/select.js";
import { staleBrewRuntimeFiles } from "../pm/brew/mirror.js";
import { staleScoopRuntimeFiles } from "../pm/scoop/deploy.js";
function warnStaleRuntime(platform) {
    const stale = platform === 'macos' ? staleBrewRuntimeFiles() : staleScoopRuntimeFiles();
    if (stale.length === 0)
        return;
    warn(`${stale.length} runtime helper(s) changed in the repo; re-run "vpr pm" to redeploy`);
}
function parseSyncDirection(args) {
    const meaningful = stripDashArgs(args);
    if (meaningful.length === 0)
        return null;
    if (isHelpFlag(meaningful)) {
        return '__HELP__';
    }
    for (const arg of meaningful) {
        const direction = normalizeSyncDirection(arg);
        if (direction)
            return direction;
    }
    return '__INVALID__';
}
async function promptSyncDirection(args) {
    const parsed = parseSyncDirection(args);
    if (parsed === '__HELP__') {
        console.log(formatSyncUsage());
        process.exit(0);
    }
    if (parsed === '__INVALID__') {
        error('Invalid sync direction; use 1, 2, backup, or restore');
        console.error(SYNC_DIRECTION_EXAMPLE);
        process.exit(1);
    }
    if (parsed && isSyncDirection(parsed))
        return parsed;
    try {
        const direction = await promptSyncDirectionMenu();
        if (!isSyncDirection(direction)) {
            error(`Invalid selection: ${direction}`);
            process.exit(1);
        }
        return direction;
    }
    catch (err) {
        const code = err?.code;
        if (code === 'CANCELLED') {
            if (!err?.printed)
                canceled();
            process.exit(130);
        }
        error(`Pass a direction in non-interactive environments: ${SYNC_DIRECTION_HINT}`);
        console.error(SYNC_DIRECTION_EXAMPLE);
        process.exit(1);
    }
}
export async function runSyncCommand(platform, args) {
    markCliInteractive();
    if (process.env.SYNC_SELECT_ALL === '1') {
        const direction = (parseSyncDirection(args) || '2');
        if (!isSyncDirection(direction)) {
            error('Invalid sync direction; use 1, 2, backup, or restore');
            return 1;
        }
        await runConfigSync({ platform, direction, fromDispatch: true });
        return 0;
    }
    const direction = await promptSyncDirection(args);
    const pairLines = readSyncPairLines(platform, direction);
    let tempFile = null;
    let itemCount = pairLines.length;
    if (process.stdin.isTTY && pairLines.length > 0) {
        const filteredFile = path.join(os.tmpdir(), `sync-filtered-${process.pid}.txt`);
        try {
            const count = await runSyncSelectPrompt({
                direction,
                rawLines: pairLines,
                outPath: filteredFile,
            });
            if (count === 0) {
                cleanupSyncTempFile(filteredFile);
                error('No configuration items to sync');
                return 1;
            }
            tempFile = filteredFile;
            itemCount = count;
            process.env.SYNC_FILTERED_PAIRS = filteredFile;
        }
        catch (err) {
            cleanupSyncTempFile(filteredFile);
            if (err?.code === 'CANCELLED') {
                if (!err.printed)
                    canceled();
                return 130;
            }
            error(err?.message || 'File selection failed');
            return 1;
        }
    }
    const message = direction === '1'
        ? `Backing up ${itemCount} files to the repository...`
        : `Restoring ${itemCount} files locally...`;
    step(message);
    try {
        await runConfigSync({ platform, direction, fromDispatch: true });
        warnStaleRuntime(platform);
        return 0;
    }
    catch (err) {
        error(err.message);
        return 1;
    }
    finally {
        delete process.env.SYNC_FILTERED_PAIRS;
        cleanupSyncTempFile(tempFile);
        if (tempFile && fs.existsSync(tempFile))
            cleanupSyncTempFile(tempFile);
    }
}
