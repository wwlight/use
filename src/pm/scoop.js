/**
 * Windows Scoop pm entry (thin wrapper).
 * Delegates to runtime/scoop/install.ps1 — installer/hooks stay in PowerShell.
 */
import path from 'node:path';
import { runPwsh } from "../core/exec.js";
import { projectRoot } from "../core/paths.js";

export function runScoopPmCommand(args = []) {
    const root = projectRoot();
    return runPwsh(path.join(root, 'runtime/scoop/install.ps1'), args, root);
}
