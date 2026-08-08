export const COLOR_PURPLE = '\x1b[1;35m';
export const COLOR_BLUE = '\x1b[34m';
export const COLOR_GREEN = '\x1b[32m';
export const COLOR_YELLOW = '\x1b[33m';
export const COLOR_RED = '\x1b[31m';
export const COLOR_DIM = '\x1b[2m';
export const COLOR_RESET = '\x1b[0m';
/** Styled section title (e.g. for menus that render their own frame). */
export function formatStepTitle(message) {
    return `${COLOR_PURPLE}➤ ${message}${COLOR_RESET}`;
}
export function info(message) {
    console.log(message);
}
export function step(message) {
    console.log(`\n${formatStepTitle(message)}`);
}
export function success(message) {
    console.log(`  ${COLOR_GREEN}✔ ${message}${COLOR_RESET}`);
}
export function note(message) {
    console.log(`  ${COLOR_BLUE}✔ ${message}${COLOR_RESET}`);
}
export function skip(message) {
    console.log(`  ${COLOR_DIM}» ${message}${COLOR_RESET}`);
}
export function warn(message) {
    console.warn(`${COLOR_YELLOW}⚠ ${message}${COLOR_RESET}`);
}
export function error(message) {
    console.error(`${COLOR_RED}✗ ${message}${COLOR_RESET}`);
}
