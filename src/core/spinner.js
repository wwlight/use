/**
 * Inline spinner for long-running operations: rendered on stderr, cleared
 * before result lines, plain fallback when stderr is not a TTY.
 */
import { COLOR_BLUE, COLOR_RESET, info } from "./log.js";
const FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
/** @param {NodeJS.WriteStream} [stream] */
function isTty(stream = process.stderr) {
    return Boolean(stream?.isTTY);
}
/** Start a spinner on stderr; returns a stop() that clears the current line. */
export function startSpinner(message) {
    let frame = 0;
    const paint = () => {
        const c = FRAMES[frame % FRAMES.length];
        frame += 1;
        process.stderr.write(`\r  ${COLOR_BLUE}${c}${COLOR_RESET} ${message}`);
    };
    paint();
    const timer = setInterval(paint, 80);
    return {
        stop() {
            clearInterval(timer);
            process.stderr.write('\r\x1b[2K');
        },
        setMessage(text) {
            message = text;
        },
    };
}
/**
 * Run an async task under a spinner. Non-TTY fallback prints the message once.
 * @template T
 * @param {string} message
 * @param {() => Promise<T>} task
 * @returns {Promise<T>}
 */
export async function runWithSpinner(message, task) {
    if (!isTty()) {
        info(message);
        return task();
    }
    const spinner = startSpinner(message);
    try {
        return await task();
    }
    finally {
        spinner.stop();
    }
}
