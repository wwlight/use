import { loadManifest } from "./manifest.js";
/**
 * Render "Usage: vpr <cmd> [<a>|<b>|...]" plus an aligned choice list and
 * examples. choices: [{ id, label }].
 */
export function formatChoiceUsage(cmd, choices, exampleArg) {
    const keys = choices.map((c) => c.id);
    const pad = Math.max(0, ...keys.map((k) => k.length));
    return [
        `Usage: vpr ${cmd} [${keys.join('|')}]`,
        '',
        ...choices.map((c) => `  ${c.id.padEnd(pad)}  ${c.label}`),
        '',
        'Examples:',
        '  ' + `vpr ${cmd}`,
        ...keys.map((k) => `  vpr ${cmd} -- ${k}`),
    ].join('\n');
}
export function formatInitUsage(common = loadManifest('common')) {
    const profiles = Object.entries(common.profiles ?? {}).map(([id, cfg]) => ({
        id,
        label: cfg.label || id,
    }));
    return formatChoiceUsage('init', profiles);
}
export function formatPmUsage(macos = loadManifest('macos')) {
    const mirrors = Object.entries(macos.brewMirrors ?? {}).map(([id, cfg]) => ({
        id,
        label: cfg.label || id,
    }));
    return formatChoiceUsage('pm', mirrors);
}
