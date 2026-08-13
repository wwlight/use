/**
 * Scoop backup import with active-mirror bucket Source rewrite.
 */
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildShellCommandLine } from "../../core/exec.js";
import { loadManifest, pathVarsForWindows, resolveProfileArtifact } from "../../core/manifest.js";
import { projectRoot } from "../../core/paths.js";
import { runWithSpinner } from "../../core/spinner.js";
import { convertToMirrorUrl, listScoopMirrors, readActiveScoopMirrorPrefix } from "./mirror.js";

function resolveBackupPath(root, profileOrPath = '') {
    const win = loadManifest('windows');
    const token = String(profileOrPath || '').trim();
    if (token && fs.existsSync(token))
        return path.resolve(token);
    if (token) {
        const name = token.startsWith('--') ? token.slice(2) : token;
        const rel = resolveProfileArtifact('windows', name);
        return path.join(root, rel);
    }
    const rel = win.scoopBackup || 'configs/windows/scoop/backup.json';
    return path.join(root, rel);
}

function writeMirroredImportFile(backupPath, activePrefix) {
    const mirrors = listScoopMirrors().filter((m) => m.id !== 'official');
    const prefixes = mirrors.map((m) => m.prefix);
    const win = loadManifest('windows');
    const githubHosts = win.scoopAccel?.githubHosts || [];
    const data = JSON.parse(fs.readFileSync(backupPath, 'utf8'));
    let changed = false;
    for (const bucket of data.buckets || []) {
        const source = String(bucket.Source || '');
        if (!source)
            continue;
        const mirrored = convertToMirrorUrl(source, activePrefix, prefixes, githubHosts);
        if (mirrored !== source) {
            bucket.Source = mirrored;
            changed = true;
        }
    }
    if (!changed)
        return backupPath;
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'use-scoop-import-'));
    const temp = path.join(tmpDir, 'backup.json');
    fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
    return temp;
}

function scoopAvailable() {
    const found = spawnSync(process.platform === 'win32' ? 'where.exe' : 'which', ['scoop'], {
        encoding: 'utf8',
        shell: false,
    });
    return (found.status ?? 1) === 0;
}

/** Async Scoop import (spinner-friendly; cpSync spawnSync blocks the event loop). */
function runScoopImport(importFile, cwd) {
    const command = buildShellCommandLine('scoop', ['import', importFile]);
    const [bin, args] = process.platform === 'win32'
        ? [process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', command]]
        : ['/bin/sh', ['-c', command]];
    return new Promise((resolve) => {
        const child = spawn(bin, args, { cwd, env: process.env, windowsHide: true });
        let stdout = '';
        let stderr = '';
        child.stdout.on('data', (chunk) => { stdout += String(chunk); });
        child.stderr.on('data', (chunk) => { stderr += String(chunk); });
        child.on('error', (err) => resolve({ status: 127, stdout, stderr: String(err.message) }));
        child.on('close', (code) => resolve({ status: code ?? 127, stdout, stderr }));
    });
}

export async function restoreScoopPackages(root = projectRoot(), profile = '') {
    const win = loadManifest('windows');
    const { scoopDir } = pathVarsForWindows(win);
    process.env.SCOOP = process.env.SCOOP || scoopDir;

    if (!scoopAvailable()) {
        throw new Error('Scoop is not installed. Run: vpr pm');
    }

    const backupPath = resolveBackupPath(root, profile);
    if (!fs.existsSync(backupPath))
        throw new Error(`Scoop backup file not found: ${backupPath}`);

    const activePrefix = readActiveScoopMirrorPrefix();
    const importFile = writeMirroredImportFile(backupPath, activePrefix);
    try {
        const label = importFile !== backupPath
            ? 'Importing Scoop packages via active mirror...'
            : 'Importing Scoop packages...';
        await runWithSpinner(label, async () => {
            const result = await runScoopImport(importFile, root);
            if ((result.status ?? 1) !== 0) {
                const logPath = path.join(root, 'error.log');
                const body = [
                    `scoop import failed: ${new Date().toISOString()}`,
                    `backup: ${backupPath}`,
                    `import: ${importFile}`,
                    '',
                    result.stdout || '',
                    result.stderr || '',
                ].join('\n');
                fs.writeFileSync(logPath, body, 'utf8');
                throw new Error(`Scoop app restore failed! See: ${logPath}`);
            }
        });
        return 0;
    }
    finally {
        if (importFile !== backupPath) {
            const tmpDir = path.dirname(importFile);
            fs.rmSync(tmpDir, { recursive: true, force: true });
        }
    }
}
