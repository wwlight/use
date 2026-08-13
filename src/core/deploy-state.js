import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
/** SHA-256 of a file's bytes (used to fingerprint deployed runtime files). */
export function fileSha256(filePath) {
    return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}
/** Read a deploy-state JSON; missing/unparseable returns null. */
export function readDeployState(statePath) {
    try {
        const parsed = JSON.parse(fs.readFileSync(statePath, 'utf8'));
        return parsed && typeof parsed === 'object' ? parsed : null;
    }
    catch {
        return null;
    }
}
/** Atomically persist a deploy-state JSON (dest abs path -> source sha256). */
export function writeDeployState(statePath, state) {
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    const temp = `${statePath}.${process.pid}.tmp`;
    fs.writeFileSync(temp, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
    fs.renameSync(temp, statePath);
}