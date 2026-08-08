import { canOpenTerminal } from "../lib/tty-term.js";
import { stripDashArgs } from "./args.js";
export function detectPlatform() {
    if (process.platform === 'darwin')
        return 'macos';
    if (process.platform === 'win32')
        return 'windows';
    return null;
}
export function requirePlatform() {
    const platform = detectPlatform();
    if (!platform) {
        throw new Error(`Unsupported operating system: ${process.platform}`);
    }
    return platform;
}
export function stripArgSeparator(args = []) {
    return stripDashArgs(args);
}
export function markCliInteractive() {
    // stdin may be a pipe (curl|bash); /dev/tty still allows menus.
    if (process.stdin.isTTY || process.env.SYNC_INTERACTIVE === '1'
        || canOpenTerminal({ allowWindowsConsole: true })) {
        process.env.SYNC_INTERACTIVE = '1';
    }
}
