import { ensureDir, expandPath, homeDir } from "./paths.js";
import { loadManifest, pathVarsForWindows } from "./manifest.js";
import { note } from "./log.js";
export function ensureManifestDirectories(platform) {
    const home = homeDir();
    const dirs = new Set();
    const common = loadManifest('common');
    for (const d of common.directories ?? [])
        dirs.add(d);
    if (platform === 'windows') {
        const win = loadManifest('windows');
        const vars = pathVarsForWindows(win);
        for (const d of win.directories ?? []) {
            dirs.add(expandPath(d, {
                home,
                scoopDir: vars.scoopDir,
                softwareAppsDir: vars.softwareAppsDir,
            }));
        }
    }
    for (const d of dirs) {
        const abs = expandPath(d, { home });
        ensureDir(abs);
        note(`Ensured directory: ${d}`);
    }
}
