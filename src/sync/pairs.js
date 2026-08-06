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
    if (platform !== 'windows' || (!local.includes('{scoopDir}') && !local.includes('{softwareAppsDir}'))) {
        return local;
    }
    const vars = pathVarsForWindows();
    return expandPath(local, {
        home: homeDir(),
        scoopDir: vars.scoopDir,
        softwareAppsDir: vars.softwareAppsDir,
    }).replace(/\\/g, '/');
}
export function readSyncItems(platform, direction, profile) {
    const liteOnly = profile === 'lite' || process.env.SYNC_PROFILE === 'lite';
    const items = [];
    for (const scope of syncScopes(platform)) {
        const manifest = loadManifest(scope);
        for (const item of manifest.sync?.toRepo ?? []) {
            if (liteOnly && item.lite === false)
                continue;
            if (direction === '1' && item.restoreOnly === true)
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
