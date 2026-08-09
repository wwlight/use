export const COLOR_PURPLE = '\x1b[1;35m';
export const COLOR_BLUE = '\x1b[34m';
export const COLOR_GREEN = '\x1b[32m';
export const COLOR_YELLOW = '\x1b[33m';
export const COLOR_RED = '\x1b[31m';
export const COLOR_DIM = '\x1b[2m';
export const COLOR_RESET = '\x1b[0m';

/** Gap after marks: "{mark} {text}". */
const MARK_GAP = ' ';
/** Nest icons start at the same column as step title text (mark width 1 + MARK_GAP). */
export const LOG_NEST_INDENT = '  ';

const MARK_STEP = '◇';
const MARK_OK = '◆';
const MARK_INFO = '●';
const MARK_SKIP = '○';
const MARK_WARN = '▲';
const MARK_ERROR = '■';

function nestLine(body) {
    return `${LOG_NEST_INDENT}${body}`;
}

/** Styled section title (e.g. for menus that render their own frame). */
export function formatStepTitle(message) {
    return `${COLOR_PURPLE}${MARK_STEP}${MARK_GAP}${message}${COLOR_RESET}`;
}
/** Top-level success title (same column as step, solid mark). */
export function formatStepSuccessTitle(message) {
    return `${COLOR_GREEN}${MARK_OK}${MARK_GAP}${message}${COLOR_RESET}`;
}
export function info(message) {
    console.log(nestLine(message));
}
export function step(message) {
    console.log(`\n${formatStepTitle(message)}`);
}
/** Phase complete: top-level ◆ on stderr (same stream as install.sh / install.ps1). */
export function stepSuccess(message) {
    process.stderr.write(`${formatStepSuccessTitle(message)}\n`);
}
export function success(message) {
    console.log(nestLine(`${COLOR_GREEN}${MARK_OK}${MARK_GAP}${message}${COLOR_RESET}`));
}
export function note(message) {
    console.log(nestLine(`${COLOR_BLUE}${MARK_INFO}${MARK_GAP}${message}${COLOR_RESET}`));
}
export function skip(message) {
    console.log(nestLine(`${COLOR_DIM}${MARK_SKIP}${MARK_GAP}${message}${COLOR_RESET}`));
}
/** Write cancel line to a stream (menu TTY should use the same stream as the frame). */
export function writeCanceled(stream = process.stderr, message = 'Canceled') {
    stream.write(`${COLOR_DIM}${message}${COLOR_RESET}\n`);
}
export function canceled(message = 'Canceled') {
    writeCanceled(process.stderr, message);
}
export function warn(message) {
    console.warn(nestLine(`${COLOR_YELLOW}${MARK_WARN}${MARK_GAP}${message}${COLOR_RESET}`));
}
export function error(message) {
    console.error(`${COLOR_RED}${MARK_ERROR}${MARK_GAP}${message}${COLOR_RESET}`);
}
