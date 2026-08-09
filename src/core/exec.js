import { spawnSync } from 'node:child_process';
import { stripArgSeparator } from "./platform.js";
export function exitStatus(result) {
    return result?.status ?? 1;
}
export function runCommand(command, args, opts = {}) {
    return spawnSync(command, args, {
        stdio: 'inherit',
        cwd: opts.cwd,
        shell: opts.shell ?? false,
        env: opts.env ?? process.env,
    });
}
export function runPwsh(scriptPath, args = [], cwd) {
    const cleanArgs = stripArgSeparator(args);
    const pwshArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...cleanArgs];
    let result = runCommand('pwsh', pwshArgs, { cwd });
    if (result.error && result.error.code === 'ENOENT') {
        result = runCommand('powershell.exe', pwshArgs, { cwd });
    }
    return exitStatus(result);
}
