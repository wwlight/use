/**
 * Shared sync-direction text and interactive entry point.
 * MENU_SELECT_OUT=<file> writes selection to file (keep TTY for menu).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runMenuSelect } from "../lib/menu-select.js";

/** Canonical directions used throughout the sync pipeline. */
export const SYNC_DIRECTION_BACKUP = '1';
export const SYNC_DIRECTION_RESTORE = '2';

const DIRECTION_ALIASES = new Map([
    ['1', SYNC_DIRECTION_BACKUP],
    ['backup', SYNC_DIRECTION_BACKUP],
    ['2', SYNC_DIRECTION_RESTORE],
    ['restore', SYNC_DIRECTION_RESTORE],
]);

export const SYNC_DIRECTION_MESSAGE = 'Choose a copy direction';
export const SYNC_DIRECTION_CHOICES = [
    { value: SYNC_DIRECTION_BACKUP, label: '1) Back up configuration -> repository' },
    { value: SYNC_DIRECTION_RESTORE, label: '2) Restore configuration -> local machine' },
];
export const SYNC_DIRECTION_HINT = '1|backup=back up config to repository, 2|restore=restore config locally';
export const SYNC_DIRECTION_EXAMPLE = 'Example: vpr sync backup  |  vpr sync restore  |  vpr sync 2';

/** Normalize CLI tokens like `1` / `backup` / `2` / `restore` to canonical `1`|`2`. */
export function normalizeSyncDirection(value) {
    if (value == null)
        return null;
    const key = String(value).trim().toLowerCase();
    return DIRECTION_ALIASES.get(key) ?? null;
}

export function isSyncDirection(value) {
    return normalizeSyncDirection(value) !== null;
}

export async function promptSyncDirectionMenu() {
    const direction = await runMenuSelect({
        message: SYNC_DIRECTION_MESSAGE,
        choices: SYNC_DIRECTION_CHOICES,
    });
    const value = normalizeSyncDirection(direction);
    if (!value) {
        throw new Error(`Invalid selection: ${direction}`);
    }
    return value;
}
const isCli = process.argv[1]
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isCli) {
    if (process.argv[2] === '--hint') {
        process.stdout.write(`${SYNC_DIRECTION_HINT}\n`);
        process.exit(0);
    }
    try {
        const direction = await promptSyncDirectionMenu();
        const text = `${direction}\n`;
        const outFile = process.env.MENU_SELECT_OUT;
        if (outFile) {
            fs.writeFileSync(outFile, text, 'utf8');
        }
        else {
            process.stdout.write(text);
        }
    }
    catch (err) {
        if (err?.code === 'CANCELLED') {
            console.error('Canceled');
            process.exit(130);
        }
        console.error(`\x1b[31m[ERROR] ${err?.message || 'Could not select sync direction'}\x1b[0m`);
        process.exit(1);
    }
}
