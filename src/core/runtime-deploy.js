import { copyFileDataOnly } from "../sync/copy.js";
import fs from 'node:fs';
import { fileSha256, readDeployState, writeDeployState } from "./deploy-state.js";
/**
 * Deploy runtime files and record a deploy-state so stale copies can be
 * detected later. plan: [{ src, dest, encoding }]. statePath records
 * `dest -> sha256(src)`.
 */
export async function deployRuntimeFiles(plan, statePath) {
    const state = {};
    for (const item of plan) {
        const { src, dest } = item;
        await copyFileDataOnly(src, dest, item.encoding ? { encoding: item.encoding } : undefined);
        state[dest] = fileSha256(src);
    }
    writeDeployState(statePath, state);
    return state;
}
/**
 * Compare deployed files against the repo sources using the recorded
 * deploy-state. Returns the list of dest paths that are missing or stale.
 * A missing state file counts every planned dest as stale.
 */
export function staleRuntimeFiles(plan, statePath) {
    const state = readDeployState(statePath) || {};
    const stale = [];
    for (const { src, dest } of plan) {
        if (!fs.existsSync(dest)) {
            stale.push(dest);
            continue;
        }
        const recorded = state[dest];
        if (!recorded || recorded !== fileSha256(src))
            stale.push(dest);
    }
    return stale;
}