import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ensureDir } from "../core/paths.js";
// /NP: hide robocopy progress (\r) so it does not clobber sync log lines.
const ROBOCOPY_FLAGS = ['/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP'];
function robocopyCopy(sourceDir, targetDir, sourceName) {
    return spawnSync('robocopy.exe', [sourceDir, targetDir, sourceName, ...ROBOCOPY_FLAGS], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
    });
}
export async function copyFileDataOnly(source, destination, opts = {}) {
    if (!fs.existsSync(source)) {
        throw new Error(`Source file not found: ${source}`);
    }
    ensureDir(path.dirname(destination));
    if (opts.encoding === 'utf8Bom') {
        const content = fs.readFileSync(source, 'utf8');
        fs.writeFileSync(destination, `\uFEFF${content.replace(/^\uFEFF/, '')}`, 'utf8');
        return;
    }
    if (process.platform === 'win32') {
        const robocopy = spawnSync('where.exe', ['robocopy.exe'], { encoding: 'utf8' });
        if (robocopy.status === 0) {
            const sourceDir = path.dirname(source);
            const sourceName = path.basename(source);
            const destDir = path.dirname(destination);
            const destName = path.basename(destination);
            if (sourceName === destName) {
                const result = robocopyCopy(sourceDir, destDir, sourceName);
                if ((result.status ?? 0) >= 8) {
                    throw new Error(`robocopy failed copying ${source} -> ${destination}`);
                }
                return;
            }
            const tempDir = path.join(destDir, `.use-copy-${process.pid}`);
            ensureDir(tempDir);
            try {
                const result = robocopyCopy(sourceDir, tempDir, sourceName);
                if ((result.status ?? 0) >= 8) {
                    throw new Error(`robocopy failed copying ${source} -> ${destination}`);
                }
                fs.renameSync(path.join(tempDir, sourceName), destination);
            }
            finally {
                fs.rmSync(tempDir, { recursive: true, force: true });
            }
            return;
        }
    }
    fs.copyFileSync(source, destination);
}
export async function backupFile(targetFile, backupDir) {
    if (!fs.existsSync(targetFile))
        return null;
    ensureDir(backupDir);
    const now = new Date();
    const yyyy = String(now.getFullYear());
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const base = `${path.basename(targetFile)}.bak.${yyyy}${mm}${dd}`;
    let n = 0;
    while (fs.existsSync(path.join(backupDir, `${base}.${n}`)))
        n += 1;
    const name = `${base}.${n}`;
    await copyFileDataOnly(targetFile, path.join(backupDir, name));
    return name;
}
