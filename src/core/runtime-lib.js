import path from 'node:path';
/**
 * Single source of truth for the src/lib files that are BOTH:
 *   - statically imported by the CLI (src/commands, pm, core), and
 *   - deployed as runtime payload (to ~/.config/homebrew/lib and
 *     ~/.config/scoop/mirror/lib) and dynamically imported by
 *     runtime/brew/mirror-menu.js / runtime/scoop/mirror/cli.js.
 *
 * brew runtime uses the UI subset; scoop runtime ships the full set
 * (it also consumes mirror-url.js at runtime).
 */
export const RUNTIME_SHARED_LIB = [
    'menu-select.js',
    'menu-viewport.js',
    'string-width.js',
    'tty-term.js',
    'mirror-url.js',
];
/**
 * Build the deploy targets for a runtime lib dir from the shared list.
 * filterFn receives each file name and returns true to include it.
 */
export function sharedLibPlan(root, targetLibDir, filterFn) {
    const names = typeof filterFn === 'function'
        ? RUNTIME_SHARED_LIB.filter(filterFn)
        : RUNTIME_SHARED_LIB;
    return names.map((name) => ({
        src: path.join(root, 'src', 'lib', name),
        dest: path.join(targetLibDir, name),
    }));
}