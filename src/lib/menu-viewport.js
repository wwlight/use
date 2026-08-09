/**
 * Sliding window for terminal menus taller than the screen.
 */

export function terminalRows(output) {
    if (output?.rows && output.rows > 0)
        return output.rows;
    return 24;
}

export function terminalColumns(output) {
    if (output?.columns && output.columns > 0)
        return output.columns;
    return 80;
}

/**
 * Keep `cursor` visible inside a window of `pageSize` rows.
 * @returns {{ offset: number, end: number }}
 */
export function menuWindow(cursor, count, offset, pageSize) {
    const size = Math.max(1, Number(pageSize) || 1);
    const n = Math.max(0, Number(count) || 0);
    if (n === 0)
        return { offset: 0, end: 0 };
    const cur = Math.min(Math.max(0, Number(cursor) || 0), n - 1);
    let start = Math.max(0, Math.min(Number(offset) || 0, Math.max(0, n - size)));
    if (cur < start)
        start = cur;
    if (cur >= start + size)
        start = cur - size + 1;
    start = Math.max(0, Math.min(start, Math.max(0, n - size)));
    return { offset: start, end: Math.min(n, start + size) };
}

/** Rows available for choice lines after fixed chrome (title / blanks / hint). */
export function menuChoicePageSize(output, chromeLines) {
    return Math.max(1, terminalRows(output) - Math.max(0, chromeLines));
}
