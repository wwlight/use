/**
 * Scoop GitHub-accel mirror catalog and interactive selection.
 */
import fs from 'node:fs';
import path from 'node:path';
import { firstValueArg, isHelpFlag } from "../../core/args.js";
import { canceled } from "../../core/log.js";
import { loadManifest } from "../../core/manifest.js";
import { scoopConfigDir } from "../../core/paths.js";
import { formatAlignedChoices, runMenuSelect } from "../../lib/menu-select.js";
import { canOpenTerminal } from "../../lib/tty-term.js";

function normalizePrefix(prefix) {
    const value = String(prefix || '').trim();
    if (!value)
        return '';
    return value.endsWith('/') ? value : `${value}/`;
}

const DEFAULT_SCOOP_REPO = 'https://github.com/ScoopInstaller/Scoop';

/** @returns {{ id: string, prefix: string, label: string }[]} */
export function listScoopMirrors() {
    const common = loadManifest('common');
    const mirrors = Array.isArray(common.githubAccel?.mirrors) ? common.githubAccel.mirrors : [];
    if (mirrors.length === 0) {
        throw new Error('common githubAccel.mirrors is empty; configure at least one mirror');
    }
    const rows = mirrors.map((item) => {
        const id = String(item.id || '').trim();
        const prefix = normalizePrefix(item.prefix);
        if (!id || !prefix)
            throw new Error('githubAccel mirrors must include id and prefix');
        return { id, prefix, label: prefix };
    });
    const win = loadManifest('windows');
    const scoopRepo = String(win.scoopAccel?.scoopRepo || DEFAULT_SCOOP_REPO).trim() || DEFAULT_SCOOP_REPO;
    rows.push({ id: 'official', prefix: '', label: scoopRepo });
    return rows;
}

export function formatScoopPmUsage() {
    const rows = listScoopMirrors();
    const pad = Math.max(0, ...rows.map((r) => r.id.length));
    return [
        `Usage: vpr pm [${rows.map((r) => r.id).join('|')}]`,
        '',
        ...rows.map((r) => `  ${r.id.padEnd(pad)}  ${r.label}`),
        '',
        'Examples:',
        '  vpr pm',
        ...rows.map((r) => `  vpr pm -- ${r.id}`),
    ].join('\n');
}

export function mirrorPrefixById(id) {
    const key = String(id || '').trim();
    const row = listScoopMirrors().find((item) => item.id === key);
    return row ? row.prefix : null;
}

export function mirrorIdByPrefix(prefix) {
    const needle = normalizePrefix(prefix);
    if (!needle)
        return 'official';
    const row = listScoopMirrors().find((item) => (
        item.prefix === needle
        || item.prefix.replace(/\/$/, '') === needle.replace(/\/$/, '')
    ));
    return row?.id || null;
}

export function formatScoopMirrorLabel(prefix) {
    if (!prefix)
        return 'Upstream';
    try {
        const host = new URL(prefix).host;
        if (host)
            return host;
    }
    catch {
        // fall through
    }
    return String(prefix).replace(/\/$/, '');
}

/**
 * Resolve mirror choice to activePrefix (empty string = official).
 * @param {string[]} args
 */
export async function resolveScoopMirror(args = []) {
    if (isHelpFlag(args)) {
        console.log(formatScoopPmUsage());
        process.exit(0);
    }
    let choice = firstValueArg(args) || '';
    if (choice.startsWith('--'))
        choice = choice.slice(2);

    // USE_ACCEL auto-selects only when non-interactive.
    const hintFromEnv = String(process.env.USE_ACCEL || '').trim();
    const interactive = canOpenTerminal({ allowWindowsConsole: true })
        || process.env.SYNC_INTERACTIVE === '1';
    if (!choice && hintFromEnv && !interactive)
        choice = hintFromEnv;

    if (choice) {
        const byId = mirrorPrefixById(choice);
        if (byId !== null)
            return byId;
        const byPrefix = mirrorIdByPrefix(choice);
        if (byPrefix !== null)
            return mirrorPrefixById(byPrefix) ?? '';
        console.log(formatScoopPmUsage());
        throw new Error(`Unknown mirror: ${choice}`);
    }

    if (!interactive) {
        console.log(formatScoopPmUsage());
        throw new Error('Pass an argument in non-interactive environments (example: vpr pm -- official)');
    }

    try {
        const rows = listScoopMirrors();
        const activeId = hintFromEnv && mirrorPrefixById(hintFromEnv) !== null ? hintFromEnv : '';
        const selected = await runMenuSelect({
            message: 'Choose a Scoop mirror',
            choices: formatAlignedChoices(rows.map((row) => ({
                value: row.id,
                name: row.id,
                detail: row.label,
            })), { activeValue: activeId }),
            initialValue: activeId,
        });
        const prefix = mirrorPrefixById(String(selected));
        if (prefix === null)
            throw new Error(`Invalid selection: ${selected}`);
        return prefix;
    }
    catch (err) {
        if (err?.code === 'CANCELLED') {
            if (!err.printed)
                canceled();
            process.exit(130);
        }
        throw err;
    }
}

export function readActiveScoopMirrorPrefix() {
    const cfgPath = path.join(scoopConfigDir(), 'mirror', 'state.json');
    if (!fs.existsSync(cfgPath))
        return '';
    try {
        const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
        return normalizePrefix(cfg.activePrefix || '');
    }
    catch {
        return '';
    }
}

export function joinScoopMirrorUrl(url, prefix, allPrefixes = []) {
    if (!url)
        return url;
    let bare = String(url).trim();
    for (const p of allPrefixes) {
        const known = normalizePrefix(p);
        if (known && bare.toLowerCase().startsWith(known.toLowerCase())) {
            bare = bare.slice(known.length);
            break;
        }
    }
    const active = normalizePrefix(prefix);
    if (!active)
        return bare;
    return active + bare;
}

export function convertToMirrorUrl(url, prefix, allPrefixes, githubHosts) {
    if (!url)
        return url;
    let bare = String(url).trim();
    for (const p of allPrefixes) {
        const known = normalizePrefix(p);
        if (known && bare.toLowerCase().startsWith(known.toLowerCase())) {
            bare = bare.slice(known.length);
            break;
        }
    }
    let host = '';
    try {
        host = new URL(bare).host;
    }
    catch {
        return bare;
    }
    if (githubHosts?.includes(host))
        return joinScoopMirrorUrl(bare, prefix, allPrefixes);
    return bare;
}
