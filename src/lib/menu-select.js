#!/usr/bin/env node
/**
 * Terminal single-select menu: move with arrows and confirm with Enter.
 * Usage: node menu-select.js <title> <value) description> [value) description ...]
 */
import path from 'node:path';
import fs from 'node:fs';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { formatStepTitle } from "../core/log.js";
import { alignMenuCheck } from "./string-width.js";
import { frameLines, openTerminal } from "./tty-term.js";
const COLOR_SELECTED = '\x1b[36m';
const COLOR_RESET = '\x1b[0m';
const CHOICE_GAP = process.platform === 'win32' ? '  ' : ' ';
export function formatChoiceLine(label, selected) {
    return `${alignMenuCheck(selected)}${CHOICE_GAP}${label}`;
}
function createSelect({ message, choices, input, output, cursor: initialCursor = 0 }) {
    let cursor = Math.min(Math.max(0, initialCursor), Math.max(0, choices.length - 1));
    let prevFrame = '';
    let state = 'active';
    /** @type {import('node:readline').Interface | undefined} */
    let rl;
    function renderActiveFrame() {
        const lines = [
            '',
            formatStepTitle(message),
            '',
            ...choices.map((item, i) => {
                const line = formatChoiceLine(item.label, i === cursor);
                return i === cursor ? `${COLOR_SELECTED}${line}${COLOR_RESET}` : line;
            }),
            '',
            '↑↓ Select  Enter Confirm  Esc/Ctrl+C Cancel',
        ];
        return `${lines.join('\n')}\n`;
    }
    function renderSubmitFrame() {
        return `\n${formatStepTitle(message)}\n${COLOR_SELECTED}${formatChoiceLine(choices[cursor].label, true)}${COLOR_RESET}\n`;
    }
    function render() {
        const frame = state === 'submit' ? renderSubmitFrame() : renderActiveFrame();
        if (frame === prevFrame)
            return;
        // One write: move to menu top + erase down + paint.
        // Avoid per-line erase/redraw; that flickers on Windows ConPTY / CONOUT$.
        let payload = '';
        if (prevFrame) {
            const cols = output.columns && output.columns > 0 ? output.columns : 80;
            const up = frameLines(prevFrame, cols);
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
        const onKeypress = (_str, key) => {
            if (state === 'submit' || !key)
                return;
            if (key.name === 'return' || key.name === 'enter') {
                state = 'submit';
                render();
                close({ endLine: false });
                resolve(String(choices[cursor].value).trim());
                return;
            }
            // Digit shortcut: pick the choice whose value equals the typed digit.
            if (/^[0-9]$/.test(key.name)) {
                const idx = choices.findIndex((item) => String(item.value).trim() === key.name);
                if (idx >= 0) {
                    cursor = idx;
                    state = 'submit';
                    render();
                    close({ endLine: false });
                    resolve(String(choices[cursor].value).trim());
                    return;
                }
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
export function parseChoice(raw) {
    const idx = raw.indexOf(')');
    if (idx <= 0) {
        throw new Error(`Expected option format "value) description"; received: ${raw}`);
    }
    const value = raw.slice(0, idx).trim();
    // Keep mark-column spacing after ")": only strip the separator space.
    const rest = raw.slice(idx + 1);
    const label = (rest.startsWith(' ') ? rest.slice(1) : rest.trimStart()) || raw;
    return { value, label };
}
/**
 * Build menu choices as "* name ---- detail" (active) or "  name ---- detail".
 * Shorter names get extra dashes so mark / dashes / detail form fixed columns.
 * Cursor glyph is rendered separately via formatChoiceLine; * marks activeValue.
 * @param {{ value: string, name?: string, detail?: string }[]} items
 * @param {{ activeValue?: string, dashWidth?: number }} [options]
 */
export function formatAlignedChoices(items, { activeValue = '', dashWidth = 10 } = {}) {
    const rows = (items || []).map((item) => ({
        value: String(item.value),
        name: String(item.name ?? item.value),
        detail: String(item.detail ?? ''),
    }));
    if (rows.length === 0)
        return [];
    const nameWidth = Math.max(...rows.map((row) => row.name.length));
    return rows.map((row) => {
        const mark = row.value === String(activeValue) ? '*' : ' ';
        const dashes = '-'.repeat(dashWidth + (nameWidth - row.name.length));
        return {
            value: row.value,
            label: `${mark} ${row.name} ${dashes} ${row.detail}`,
        };
    });
}
export async function runMenuSelect({ message, choices, initialValue }) {
    const term = openTerminal({ allowWindowsConsole: true });
    if (!term) {
        throw new Error('Could not open an interactive terminal');
    }
    try {
        let cursor = 0;
        if (initialValue != null && initialValue !== '') {
            const idx = choices.findIndex((item) => String(item.value) === String(initialValue));
            if (idx >= 0)
                cursor = idx;
        }
        return await createSelect({
            message,
            choices,
            input: term.input,
            output: term.output,
            cursor,
        });
    }
    finally {
        term.close();
    }
}
const isCli = process.argv[1]
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isCli) {
    const message = process.argv[2];
    const rawChoices = process.argv.slice(3);
    if (!message || rawChoices.length === 0) {
        console.error('Usage: node menu-select.js <title> <value) description> [value) description ...]');
        process.exit(1);
    }
    try {
        const choices = rawChoices.map(parseChoice);
        const value = await runMenuSelect({
            message,
            choices,
            initialValue: process.env.MENU_SELECT_INITIAL,
        });
        const text = `${String(value).trim()}\n`;
        const outFile = process.env.MENU_SELECT_OUT;
        if (outFile) {
            fs.writeFileSync(outFile, text, 'utf8');
        }
        else {
            process.stdout.write(text);
        }
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
