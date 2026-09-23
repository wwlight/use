import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ensureDir } from "./paths.js";
// /NP: hide robocopy progress (\r) so it does not clobber sync log lines.
const ROBOCOPY_FLAGS = ['/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP'];
/** Cache the `where robocopy` probe: it used to spawn once per file copy. */
let robocopyAvailable = null;
function isRobocopyAvailable() {
    if (robocopyAvailable === null) {
        const robocopy = spawnSync('where.exe', ['robocopy.exe'], { encoding: 'utf8' });
        robocopyAvailable = robocopy.status === 0;
    }
    return robocopyAvailable;
}
function robocopyCopy(sourceDir, targetDir, sourceName) {
    return spawnSync('robocopy.exe', [sourceDir, targetDir, sourceName, ...ROBOCOPY_FLAGS], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
    });
}
/** Byte-identical: size gate first, then a single buffer compare. */
function filesEqual(source, destination) {
    try {
        const srcStat = fs.statSync(source);
        const dstStat = fs.statSync(destination);
        if (!dstStat.isFile() || srcStat.size !== dstStat.size)
            return false;
    }
    catch {
        return false;
    }
    return fs.readFileSync(source).equals(fs.readFileSync(destination));
}
export async function copyFileDataOnly(source, destination, opts = {}) {
    if (!fs.existsSync(source)) {
        throw new Error(`Source file not found: ${source}`);
    }
    ensureDir(path.dirname(destination));
    if (opts.encoding === 'utf8Bom') {
        const content = fs.readFileSync(source, 'utf8');
        const next = `\uFEFF${content.replace(/^\uFEFF/, '')}`;
        if (!opts.force && fs.existsSync(destination) && fs.readFileSync(destination, 'utf8') === next)
            return;
        fs.writeFileSync(destination, next, 'utf8');
        return;
    }
    if (!opts.force && filesEqual(source, destination))
        return;
    if (process.platform === 'win32' && isRobocopyAvailable()) {
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
    fs.copyFileSync(source, destination);
}
const DIRECTORY_SKIP = new Set(['node_modules', '.git', '.DS_Store']);
function directorySkip(name, exclude) {
    return DIRECTORY_SKIP.has(name) || exclude.has(name);
}
/**
 * Mirror `source` onto `destination`.
 * Skipped names are left untouched on the destination, including extras that exist only there.
 */
export async function syncDirectory(source, destination, opts = {}) {
    if (!fs.existsSync(source) || !fs.statSync(source).isDirectory()) {
        throw new Error(`Source directory not found: ${source}`);
    }
    const exclude = new Set(opts.exclude ?? []);
    ensureDir(destination);
    await copyDirectoryEntries(source, destination, exclude);
    pruneDirectoryEntries(source, destination, exclude);
}
function unlinkIfSymlink(target) {
    try {
        if (fs.lstatSync(target).isSymbolicLink()) {
            fs.unlinkSync(target);
            return true;
        }
    }
    catch {
        return false;
    }
    return false;
}
async function copyDirectoryEntries(source, destination, exclude) {
    for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
        if (directorySkip(entry.name, exclude) || entry.isSymbolicLink())
            continue;
        const from = path.join(source, entry.name);
        const to = path.join(destination, entry.name);
        unlinkIfSymlink(to);
        if (entry.isDirectory()) {
            if (fs.existsSync(to) && !fs.statSync(to).isDirectory())
                fs.rmSync(to, { force: true });
            ensureDir(to);
            await copyDirectoryEntries(from, to, exclude);
            continue;
        }
        if (!entry.isFile())
            continue;
        if (fs.existsSync(to) && fs.statSync(to).isDirectory())
            fs.rmSync(to, { recursive: true, force: true });
        await copyFileDataOnly(from, to);
    }
}
function pruneDirectoryEntries(source, destination, exclude) {
    if (!fs.existsSync(destination))
        return;
    for (const entry of fs.readdirSync(destination, { withFileTypes: true })) {
        if (directorySkip(entry.name, exclude))
            continue;
        const from = path.join(source, entry.name);
        const to = path.join(destination, entry.name);
        if (entry.isSymbolicLink() || !fs.existsSync(from)) {
            fs.rmSync(to, { recursive: true, force: true });
            continue;
        }
        if (entry.isDirectory() && fs.statSync(from).isDirectory())
            pruneDirectoryEntries(from, to, exclude);
    }
}
export async function backupDirectory(targetDir, backupDir, exclude = []) {
    if (!fs.existsSync(targetDir))
        return null;
    ensureDir(backupDir);
    const now = new Date();
    const yyyy = String(now.getFullYear());
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const base = `${path.basename(targetDir)}.bak.${yyyy}${mm}${dd}`;
    let n = 0;
    while (fs.existsSync(path.join(backupDir, `${base}.${n}`)))
        n += 1;
    const name = `${base}.${n}`;
    await syncDirectory(targetDir, path.join(backupDir, name), { exclude });
    return name;
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
