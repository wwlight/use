import { loadManifest } from "./manifest.js";
export function formatInitUsage(common = loadManifest('common')) {
    const keys = Object.keys(common.profiles ?? {});
    const pad = Math.max(0, ...keys.map((k) => k.length));
    return [
        `Usage: vpr init [${keys.join('|')}]`,
        '',
        ...keys.map((k) => `  ${k.padEnd(pad)}  ${common.profiles[k].label}`),
        '',
        'Examples:',
        '  vpr init',
        ...keys.map((k) => `  vpr init -- ${k}`),
    ].join('\n');
}
export function formatPmUsage(macos = loadManifest('macos')) {
    const keys = Object.keys(macos.brewMirrors ?? {});
    const pad = Math.max(0, ...keys.map((k) => k.length));
    return [
        `Usage: vpr pm [${keys.join('|')}]`,
        '',
        ...keys.map((k) => `  ${k.padEnd(pad)}  ${macos.brewMirrors[k].label}`),
        '',
        'Examples:',
        '  vpr pm',
        ...keys.map((k) => `  vpr pm -- ${k}`),
    ].join('\n');
}
