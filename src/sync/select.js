#!/usr/bin/env node
/**
 * Terminal multi-select using only Node built-ins, modeled after @clack/core.
 */
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { truncateWidth } from "../lib/string-width.js";
import { frameLines, openTerminal } from "../lib/tty-term.js";
import { formatStepTitle } from "../core/log.js";
import { formatLocalDisplay, formatRepoDisplay } from "./pairs.js";
export function formatSyncChoiceLine(label, { selected = false, active = false, labelMax = 30, widthOptions = {} } = {}) {
    // Active row only: ◆ checked / ◇ unchecked; idle blank. Selection mark stays in [ ].
    const pointer = active ? (selected ? '◆' : '◇') : ' ';
    const mark = selected ? '✔' : ' ';
    return `${pointer} [${mark}] ${truncateWidth(label, labelMax, widthOptions)}`;
}
function parseItems(rawLines) {
    return rawLines.map((line) => {
        const [local, repo, backup, , defaultSelected] = line.split('\t');
        return {
            local,
            repo,
            backup,
            selected: defaultSelected !== '0',
            line,
        };
    });
}
function writeResult(lines, outPath) {
    const content = `${lines.join('\n')}\n`;
    if (outPath)
        fs.writeFileSync(outPath, content);
    else
        process.stdout.write(content);
}
function columns(output) {
    if (output.columns && output.columns > 0)
        return output.columns;
    if (process.platform !== 'win32') {
        try {
            const [, cols] = execSync('stty size', { encoding: 'utf8' }).trim().split(/\s+/);
            const n = Number.parseInt(cols, 10);
            if (n > 0)
                return n;
        }
        catch { }
    }
    return 80;
}
function isToggleKey(str, key) {
    return str === ' ' || key?.name === 'space' || key?.name === 'x';
}
function createMultiselect({ message, choices, input, output }) {
    let cursor = 0;
    let prevFrame = '';
    let state = 'active';
    let error = '';
    /** @type {import('node:readline').Interface | undefined} */
    let rl;
    function renderActiveFrame() {
        const width = columns(output);
        const labelMax = Math.max(30, width - 8);
        const lines = [
            '',
            formatStepTitle(message),
            '',
            ...choices.map((item, i) => formatSyncChoiceLine(item.label, {
                selected: item.selected,
                active: i === cursor,
                labelMax,
            })),
            '',
            '↑↓ Move  Space/x Toggle  Enter Confirm  Esc/Ctrl+C Cancel',
        ];
        if (error)
            lines.push('', error);
        return `${lines.join('\n')}\n`;
    }
    function renderSubmitFrame() {
        const picked = choices.filter((c) => c.selected);
        return `\n${formatStepTitle(message)}\n${picked.length} selected\n`;
    }
    function render() {
        const frame = state === 'submit' ? renderSubmitFrame() : renderActiveFrame();
        if (frame === prevFrame)
            return;
        // One write: move to menu top + erase down + paint.
        // Avoid per-write erase/redraw; that flickers on Windows ConPTY / CONOUT$.
        let payload = '';
        if (prevFrame) {
            const up = frameLines(prevFrame);
            if (up > 0)
                payload += `\x1B[${up}A\r`;
            payload += '\x1B[J';
        }
        else {
            payload += '\x1B[?25l';
        }
        payload += frame;
        output.write(payload);
        prevFrame = frame;
    }
    return new Promise((resolve, reject) => {
        const canInteract = input.isTTY || process.env.SYNC_INTERACTIVE === '1';
        if (!canInteract) {
            reject(new Error('Not a TTY'));
            return;
        }
        try {
            if (typeof input.setRawMode === 'function') {
                input.setRawMode(true);
            }
        }
        catch (err) {
            reject(new Error(`Could not enter interactive mode: ${err.message}`));
            return;
        }
        // Do not bind output / terminal:true; readline adds a newline and offsets restoreFrame.
        rl = readline.createInterface({ input });
        readline.emitKeypressEvents(input, rl);
        const close = ({ endLine = true } = {}) => {
            input.removeListener('keypress', onKeypress);
            if (endLine)
                output.write('\n');
            output.write('\x1B[?25h');
            if (typeof input.setRawMode === 'function') {
                input.setRawMode(false);
            }
            rl?.close();
            rl = undefined;
        };
        const onKeypress = (str, key) => {
            if (state === 'submit')
                return;
            if (isToggleKey(str, key)) {
                choices[cursor].selected = !choices[cursor].selected;
                error = '';
                render();
                return;
            }
            if (!key)
                return;
            if (key.name === 'return' || key.name === 'enter') {
                const picked = choices.filter((c) => c.selected);
                if (picked.length === 0) {
                    error = 'Select at least one item';
                    render();
                    return;
                }
                error = '';
                state = 'submit';
                render();
                close({ endLine: false });
                resolve(picked);
                return;
            }
            if (key.name === 'up') {
                cursor = (cursor - 1 + choices.length) % choices.length;
            }
            else if (key.name === 'down') {
                cursor = (cursor + 1) % choices.length;
            }
            else if (key.ctrl && key.name === 'c') {
                close();
                const err = new Error('Canceled');
                err.code = 'CANCELLED';
                reject(err);
                return;
            }
            else if (key.name === 'escape') {
                close();
                const err = new Error('Canceled');
                err.code = 'CANCELLED';
                reject(err);
                return;
            }
            else {
                return;
            }
            render();
        };
        input.on('keypress', onKeypress);
        render();
    });
}
export async function runSyncSelectPrompt({ direction, rawLines, outPath }) {
    const items = parseItems(rawLines);
    if (items.length === 0) {
        writeResult(rawLines, outPath);
        return 0;
    }
    const term = openTerminal({ allowWindowsConsole: true });
    if (!term) {
        if (process.env.SYNC_INTERACTIVE === '1') {
            throw new Error('Could not open an interactive terminal; use SYNC_SELECT_ALL=1 to skip selection');
        }
        writeResult(rawLines, outPath);
        return rawLines.length;
    }
    const title = direction === '1' ? 'Choose files to back up to the repository' : 'Choose files to restore locally';
    const choices = items.map((item) => ({
        label: direction === '1' ? formatRepoDisplay(item.repo) : formatLocalDisplay(item.local),
        selected: item.selected,
        line: item.line,
    }));
    try {
        const picked = await createMultiselect({
            message: title,
            choices,
            input: term.input,
            output: term.output,
        });
        writeResult(picked.map((c) => c.line), outPath);
        return picked.length;
    }
    catch (err) {
        if (process.env.SYNC_INTERACTIVE === '1') {
            throw err;
        }
        writeResult(rawLines, outPath);
        return rawLines.length;
    }
    finally {
        term.close();
    }
}
const isCli = process.argv[1]
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isCli) {
    const direction = process.argv[2];
    const pairsPath = process.argv[3];
    const outPath = process.argv[4];
    if (!direction || !pairsPath) {
        console.error('Usage: node src/sync/select.js <1|2> <pairs-file> [out-file]');
        process.exit(1);
    }
    const rawLines = fs.readFileSync(pairsPath, 'utf8').trim().split('\n').filter(Boolean);
    try {
        await runSyncSelectPrompt({ direction, rawLines, outPath });
    }
    catch (err) {
        if (err.code === 'CANCELLED') {
            console.error('Canceled');
            process.exit(130);
        }
        console.error(err?.message || String(err));
        process.exit(1);
    }
}
