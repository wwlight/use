const COLOR_PURPLE = '\x1b[1;35m';
export const COLOR_BLUE = '\x1b[34m';
const COLOR_GREEN = '\x1b[32m';
const COLOR_YELLOW = '\x1b[33m';
const COLOR_RED = '\x1b[31m';
const COLOR_DIM = '\x1b[2m';
export const COLOR_RESET = '\x1b[0m';

/** Gap after marks: "{mark} {text}". */
const MARK_GAP = ' ';

const MARK_STEP = '◇';
const MARK_SUCCESS = '✓';
const MARK_INFO = '●';
const MARK_SKIP = '○';
const MARK_WARN = '▲';
const MARK_ERROR = '■';

/** All progress/result lines go to stderr; stdout stays free for command output. */
const LOG_STREAM = process.stderr;

/** Single mark-styling primitive: "{mark} {message}" wrapped in color. */
function formatMark(mark, color, message) {
    return `${color}${mark}${MARK_GAP}${message}${COLOR_RESET}`;
}

/** Styled section title (e.g. for menus that render their own frame). */
export function formatStepTitle(message) {
    return formatMark(MARK_STEP, COLOR_PURPLE, message);
}

function writeLine(body) {
    LOG_STREAM.write(`${body}\n`);
}

/** Process line: dim mark, kept left-aligned (flat layout). */
export function info(message, { color = COLOR_DIM } = {}) {
    writeLine(formatMark(MARK_INFO, color, message));
}
/** Item-level result line: blue mark. Contrasts with dim process lines. */
export function note(message) {
    info(message, { color: COLOR_BLUE });
}
export function step(message) {
    writeLine(`\n${formatStepTitle(message)}`);
}
export function success(message) {
    writeLine(formatMark(MARK_SUCCESS, COLOR_GREEN, message));
}
export function skip(message) {
    writeLine(formatMark(MARK_SKIP, COLOR_DIM, message));
}
/** Write cancel line to a stream (menu TTY should use the same stream as the frame). */
export function writeCanceled(stream = LOG_STREAM, message = 'Canceled') {
    stream.write(`${COLOR_DIM}${message}${COLOR_RESET}\n`);
}
export function canceled(message = 'Canceled') {
    writeCanceled(LOG_STREAM, message);
}
export function warn(message) {
    writeLine(formatMark(MARK_WARN, COLOR_YELLOW, message));
}
export function error(message) {
    writeLine(formatMark(MARK_ERROR, COLOR_RED, message));
}
/** Print a fatal error; with USE_DEBUG=1 also print the stack for troubleshooting. */
export function handleFatalError(err) {
    if (process.env.USE_DEBUG === '1' && err?.stack)
        console.error(err.stack);
    else
        error(err?.message || String(err));
}