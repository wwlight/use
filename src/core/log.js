export function info(message) {
    console.log(`\x1b[32m[INFO] ${message}\x1b[0m`);
}
export function step(message) {
    console.log(`\x1b[34m[INFO] ${message}\x1b[0m`);
}
export function warn(message) {
    console.warn(`\x1b[33m[WARN] ${message}\x1b[0m`);
}
export function error(message) {
    console.error(`\x1b[31m[ERROR] ${message}\x1b[0m`);
}
