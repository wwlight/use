/**
 * Open terminal streams for interaction, including piped shells and captured stdout.
 */
import fs from 'node:fs';
import tty from 'node:tty';
import { stringWidth } from "./string-width.js";

function stripAnsi(text) {
    return String(text ?? '').replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, '');
}

/** Screen rows occupied by a painted frame (accounts for wrap when columns > 0). */
export function frameLines(frame, columns = 0) {
    if (!frame)
        return 0;
    const parts = frame.split('\n');
    let count = 0;
    for (let i = 0; i < parts.length; i++) {
        if (i === parts.length - 1 && parts[i] === '')
            continue;
        if (columns > 0) {
            const w = stringWidth(stripAnsi(parts[i]), { ambiguousWide: false });
            count += Math.max(1, Math.ceil(Math.max(0, w) / columns) || 1);
        }
        else {
            count += 1;
        }
    }
    return count;
}
export function restoreFrame(output, frame) {
    const up = frameLines(frame, output?.columns || 0);
    if (up > 0)
        output.write(`\x1B[${up}A\r`);
}
function openWindowsConsole() {
    try {
        const fdIn = fs.openSync('CONIN$', 'r');
        const fdOut = fs.openSync('CONOUT$', 'w');
        return {
            input: new tty.ReadStream(fdIn),
            output: new tty.WriteStream(fdOut),
            owned: true,
            close() {
                // Close input only; destroying CONOUT$ can clear or corrupt the console.
                if (!this.input.destroyed)
                    this.input.destroy();
            },
        };
    }
    catch {
        return null;
    }
}
function isVsCodeConPty() {
    const term = String(process.env.TERM_PROGRAM || '').toLowerCase();
    return term === 'vscode' || term === 'cursor' || Boolean(process.env.VSCODE_INJECTION);
}
/**
 * @param {{ allowWindowsConsole?: boolean }} [options]
 * - allowWindowsConsole: whether to allow CONIN$/CONOUT$ on Windows.
 *   Defaults to SYNC_INTERACTIVE=1; disabled under Cursor/VS Code ConPTY.
 */
export function openTerminal(options = {}) {
    const allowWindowsConsole = options.allowWindowsConsole
        ?? process.env.SYNC_INTERACTIVE === '1';
    if (process.stdin.isTTY && process.stdout.isTTY) {
        return {
            input: process.stdin,
            output: process.stdout,
            owned: false,
            close() { },
        };
    }
    // PowerShell `$x = & node ...` captures stdout; stderr is often still a TTY.
    if (process.stdin.isTTY && process.stderr.isTTY) {
        return {
            input: process.stdin,
            output: process.stderr,
            owned: false,
            close() { },
        };
    }
    if (process.platform === 'win32') {
        // Under Cursor/VS Code ConPTY, CONOUT$ is hidden and CONIN$ receives no keys.
        if (allowWindowsConsole && !isVsCodeConPty()) {
            const cons = openWindowsConsole();
            if (cons)
                return cons;
        }
        if (process.stdin.isTTY) {
            return {
                input: process.stdin,
                output: process.stderr.isTTY ? process.stderr : process.stdout,
                owned: false,
                close() { },
            };
        }
        return null;
    }
    try {
        const fd = fs.openSync('/dev/tty', 'r+');
        return {
            input: new tty.ReadStream(fd),
            output: new tty.WriteStream(fd),
            owned: true,
            close() {
                if (!this.input.destroyed)
                    this.input.destroy();
                if (!this.output.destroyed)
                    this.output.destroy();
            },
        };
    }
    catch {
        return null;
    }
}

/**
 * True when a controlling TTY is available (incl. /dev/tty under curl|bash).
 * @param {{ allowWindowsConsole?: boolean }} [options]
 */
export function canOpenTerminal(options = {}) {
    const term = openTerminal(options);
    if (!term)
        return false;
    term.close();
    return true;
}
