import fs from 'node:fs';
import { expandPath, formatLocalDisplay, formatRepoDisplay, homeDir, } from "../core/paths.js";
import { pathVarsForWindows, syncScopes, loadManifest, } from "../core/manifest.js";
export { formatLocalDisplay, formatRepoDisplay };
export function toPairLine(item) {
    const backup = item.backup ? '1' : '0';
    const encoding = item.encoding ?? '';
    const defaultSelected = item.defaultSelected === false ? '0' : '1';
    return `${item.local}\t${item.repo}\t${backup}\t${encoding}\t${defaultSelected}`;
}
export function parsePairLine(line) {
    const [local, repo, backup, encoding = '', defaultSelected = '1'] = line.split('\t');
    return {
        local,
        repo,
        backup: backup === '1',
        encoding,
        defaultSelected: defaultSelected !== '0',
        rawLine: line,
    };
}
function normalizeLocalForPair(local, platform) {
    if (
        platform !== 'windows'
        || (
            !local.includes('{scoopDir}')
            && !local.includes('{softwareAppsDir}')
            && !local.includes('{scoopConfigDir}')
        )
    ) {
        return local;
    }
    const vars = pathVarsForWindows();
    return expandPath(local, {
        home: homeDir(),
        scoopDir: vars.scoopDir,
        scoopConfigDir: vars.scoopConfigDir,
        softwareAppsDir: vars.softwareAppsDir,
    }).replace(/\\/g, '/');
}
/**
 * Sort key so platform + common merge keeps path groups together in the menu.
 * Groups: home dotfiles → ~/.zsh → ~/.config → ~/Documents → other.
 */
export function syncGroupKey(local, home = homeDir()) {
    const display = formatLocalDisplay(local, home).replace(/\\/g, '/');
    if (display.startsWith('~/')) {
        const rest = display.slice(2);
        if (!rest.includes('/'))
            return '0:~';
        const top = rest.split('/')[0];
        if (top === '.zsh')
            return '1:~/.zsh';
        if (top === '.config')
            return '2:~/.config';
        if (top === 'Documents')
            return '3:~/Documents';
        return `9:~/${top}`;
    }
    const parts = display.split('/').filter(Boolean);
    const prefix = parts.slice(0, Math.min(3, parts.length)).join('/');
    return `9:other:${prefix}`;
}
function compareSyncItems(a, b, home = homeDir()) {
    const ga = syncGroupKey(a.local, home);
    const gb = syncGroupKey(b.local, home);
    if (ga !== gb)
        return ga < gb ? -1 : 1;
    const da = formatLocalDisplay(a.local, home).replace(/\\/g, '/');
    const db = formatLocalDisplay(b.local, home).replace(/\\/g, '/');
    if (da !== db)
        return da < db ? -1 : 1;
    return a.repo < b.repo ? -1 : a.repo > b.repo ? 1 : 0;
}
export function readSyncItems(platform, direction, profile) {
    const liteOnly = profile === 'lite' || process.env.SYNC_PROFILE === 'lite';
    const skipPmHelpers = process.env.SYNC_SKIP_PM_HELPERS === '1';
    const items = [];
    for (const scope of syncScopes(platform)) {
        const manifest = loadManifest(scope);
        for (const item of manifest.sync?.toRepo ?? []) {
            if (liteOnly && item.lite === false)
                continue;
            if (direction === '1' && item.restoreOnly === true)
                continue;
            if (skipPmHelpers && item.pmHelper)
                continue;
            const normalized = {
                ...item,
                local: normalizeLocalForPair(item.local, platform),
            };
            items.push({
                local: normalized.local,
                repo: normalized.repo,
                backup: Boolean(normalized.backup),
                encoding: normalized.encoding ?? '',
                defaultSelected: normalized.defaultSelected !== false,
                rawLine: toPairLine(normalized),
            });
        }
    }
    items.sort((a, b) => compareSyncItems(a, b));
    return items;
}
export function readSyncPairLines(platform, direction, profile) {
    return readSyncItems(platform, direction, profile).map((item) => item.rawLine);
}
export function cleanupSyncTempFile(filePath) {
    if (!filePath)
        return;
    try {
        fs.unlinkSync(filePath);
    }
    catch {
        // already consumed
    }
}
