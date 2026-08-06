import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { error } from "../core/log.js";
import { markCliInteractive } from "../core/platform.js";
import { SYNC_DIRECTION_EXAMPLE, SYNC_DIRECTION_HINT, isSyncDirection, promptSyncDirectionMenu, } from "../sync/direction.js";
import { runConfigSync } from "../sync/engine.js";
import { cleanupSyncTempFile, readSyncPairLines } from "../sync/pairs.js";
import { runSyncSelectPrompt } from "../sync/select.js";
function parseSyncDirection(args) {
    const meaningful = args.filter((arg) => arg !== '--');
    if (meaningful.length === 0)
        return null;
    if (meaningful.some((arg) => arg === '-h' || arg === '--help' || arg === 'help')) {
        return '__HELP__';
    }
    for (const arg of meaningful) {
        if (arg === '1' || arg === '2')
            return arg;
    }
    return '__INVALID__';
}
async function promptSyncDirection(args) {
    const parsed = parseSyncDirection(args);
    if (parsed === '__HELP__') {
        console.log([
            'Usage: vpr sync [1|2]',
            '',
            '  1  Back up configuration -> repository',
            '  2  Restore configuration -> local machine',
            '',
            'Examples:',
            '  vpr sync',
            '  vpr sync -- 1',
            '  vpr sync -- 2',
        ].join('\n'));
        process.exit(0);
    }
    if (parsed === '__INVALID__') {
        error('Invalid sync direction; use 1 or 2');
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
            console.error('Canceled');
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
            error('Invalid sync direction; use 1 or 2');
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
                console.error('Canceled');
                return 130;
            }
            error(err?.message || 'File selection failed');
            return 1;
        }
    }
    const message = direction === '1'
        ? `Backing up ${itemCount} files to the repository...`
        : `Restoring ${itemCount} files locally...`;
    console.log(`\x1b[34m[INFO] ${message}\x1b[0m`);
    try {
        await runConfigSync({ platform, direction, fromDispatch: true });
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
