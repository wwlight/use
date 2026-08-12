import { spawnSync } from 'node:child_process';
import { stripArgSeparator } from "./platform.js";
export function exitStatus(result) {
    return result?.status ?? 1;
}
/**
 * Build a shell command line (avoids Node DEP0190, which fires when an args
 * array is passed alongside shell:true since args are only concatenated).
 */
export function buildShellCommandLine(command, args = []) {
    return [String(command), ...args].map((part) => {
        const s = String(part);
        if (!/[\s"]/.test(s))
            return s;
        // Trust already-quoted fragments (e.g. `install.cmd "C:\path"`).
        if (s.includes('"'))
            return s;
        return `"${s}"`;
    }).join(' ');
}
export function runCommand(command, args, opts = {}) {
    if (opts.shell) {
        return spawnSync(buildShellCommandLine(command, args), {
            stdio: 'inherit',
            cwd: opts.cwd,
            env: opts.env ?? process.env,
            shell: true,
            timeout: opts.timeoutMs,
        });
    }
    return spawnSync(command, args, {
        stdio: 'inherit',
        cwd: opts.cwd,
        shell: false,
        env: opts.env ?? process.env,
        timeout: opts.timeoutMs,
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
