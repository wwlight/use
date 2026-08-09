import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ensureDir, expandPath, formatLocalDisplay, homeDir, projectRoot } from "../core/paths.js";
import { step, stepSuccess, success, warn } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { copyFileDataOnly } from "../sync/copy.js";
const BEGIN = '# >>> use-homebrew';
const END = '# <<< use-homebrew';
export function brewConfigDir() {
    const xdg = process.env.XDG_CONFIG_HOME;
    return xdg ? path.join(xdg, 'homebrew') : path.join(homeDir(), '.config', 'homebrew');
}
export function brewMirrorConfigFile() {
    return path.join(brewConfigDir(), 'mirror.zsh');
}
export function readBrewMirrorCatalog(catalogPath) {
    const file = catalogPath
        || path.join(projectRoot(), loadManifest('macos').brewMirrorCatalog || 'configs/macos/brew/mirrors.tsv');
    const text = fs.readFileSync(file, 'utf8');
    const rows = [];
    for (const line of text.split(/\r?\n/)) {
        if (!line || line.startsWith('#'))
            continue;
        const [id, label, apiDomain, bottleDomain, brewGitRemote] = line.split('\t');
        if (!id)
            continue;
        rows.push({
            id,
            label: label || id,
            apiDomain: apiDomain === '-' ? '' : (apiDomain || ''),
            bottleDomain: bottleDomain === '-' ? '' : (bottleDomain || ''),
            brewGitRemote: brewGitRemote === '-' ? '' : (brewGitRemote || ''),
        });
    }
    return rows;
}
export function findBrewBinary() {
    const which = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['brew'], {
        encoding: 'utf8',
        shell: false,
    });
    const fromPath = (which.stdout || '').split(/\r?\n/).map((s) => s.trim()).find(Boolean);
    if (fromPath && fromPath !== 'brew' && fs.existsSync(fromPath))
        return fromPath;
    for (const candidate of ['/opt/homebrew/bin/brew', '/usr/local/bin/brew']) {
        try {
            fs.accessSync(candidate, fs.constants.X_OK);
            return candidate;
        }
        catch {
            // continue
        }
    }
    return null;
}
export function removeBrewMirrorLegacy() {
    for (const p of [
        path.join(homeDir(), '.zsh/functions/brew-mirror.zsh'),
        path.join(brewConfigDir(), 'manage.zsh'),
        path.join(brewConfigDir(), 'brew-mirror.zsh'),
        path.join(brewConfigDir(), 'lib', 'menu.js'),
        path.join(brewConfigDir(), 'lib', 'menu.mjs'),
    ]) {
        try {
            if (fs.existsSync(p))
                fs.unlinkSync(p);
        }
        catch (err) {
            warn(`Could not remove legacy brew-mirror helper: ${err.message}`);
        }
    }
}
export function writeBrewMirrorConfig(mirrorId) {
    const rows = readBrewMirrorCatalog();
    const row = rows.find((r) => r.id === mirrorId);
    if (!row)
        throw new Error(`Unknown Homebrew mirror: ${mirrorId}`);
    ensureDir(brewConfigDir());
    const lines = [
        '# Managed by brew mirror. Do not edit.',
        `export USE_HOMEBREW_MIRROR=${mirrorId}`,
    ];
    if (!row.apiDomain || mirrorId === 'official') {
        lines.push('unset HOMEBREW_API_DOMAIN');
        lines.push('unset HOMEBREW_BOTTLE_DOMAIN');
        lines.push('unset HOMEBREW_BREW_GIT_REMOTE');
    }
    else {
        lines.push(`export HOMEBREW_API_DOMAIN=${row.apiDomain}`);
        lines.push(`export HOMEBREW_BOTTLE_DOMAIN=${row.bottleDomain}`);
        lines.push(`export HOMEBREW_BREW_GIT_REMOTE=${row.brewGitRemote}`);
    }
    const content = `${lines.join('\n')}\n`;
    const dest = brewMirrorConfigFile();
    const temp = `${dest}.${process.pid}.tmp`;
    fs.writeFileSync(temp, content, 'utf8');
    fs.renameSync(temp, dest);
    return row;
}
export function brewMirrorEnv(mirrorId) {
    const row = writeBrewMirrorConfig(mirrorId);
    const env = { ...process.env, USE_HOMEBREW_MIRROR: mirrorId };
    if (!row.apiDomain || mirrorId === 'official') {
        delete env.HOMEBREW_API_DOMAIN;
        delete env.HOMEBREW_BOTTLE_DOMAIN;
        delete env.HOMEBREW_BREW_GIT_REMOTE;
    }
    else {
        env.HOMEBREW_API_DOMAIN = row.apiDomain;
        env.HOMEBREW_BOTTLE_DOMAIN = row.bottleDomain;
        env.HOMEBREW_BREW_GIT_REMOTE = row.brewGitRemote;
    }
    return env;
}
function shellQuote(value) {
    return `'${value.replace(/'/g, `'\\''`)}'`;
}
/** Portable zsh refs — avoid baking $HOME absolute paths (usernames) into .zprofile. */
const ZPROFILE_MIRROR_ZSH = '"${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/mirror.zsh"';
const ZPROFILE_MIRROR_CLI = '"${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/mirror-cli.zsh"';
export function ensureBrewZprofile() {
    removeBrewMirrorLegacy();
    const zprofile = expandPath('~/.zprofile', { home: homeDir() });
    const brew = findBrewBinary();
    let existing = '';
    if (fs.existsSync(zprofile)) {
        existing = fs.readFileSync(zprofile, 'utf8');
        const begins = existing.split(BEGIN).length - 1;
        const ends = existing.split(END).length - 1;
        if (begins !== ends || begins > 1) {
            throw new Error(`Malformed ${zprofile}: mismatched use-homebrew markers`);
        }
        existing = existing
            .split(/\r?\n/)
            .reduce((acc, line) => {
            if (line === BEGIN) {
                acc.skip = true;
                return acc;
            }
            if (line === END) {
                acc.skip = false;
                return acc;
            }
            if (!acc.skip)
                acc.lines.push(line);
            return acc;
        }, { lines: [], skip: false })
            .lines
            .join('\n')
            .replace(/\n+$/, '');
    }
    const block = [
        BEGIN,
        brew ? `eval "$(${shellQuote(brew)} shellenv)"` : '',
        `[[ -r ${ZPROFILE_MIRROR_ZSH} ]] && . ${ZPROFILE_MIRROR_ZSH}`,
        `[[ -r ${ZPROFILE_MIRROR_CLI} ]] && . ${ZPROFILE_MIRROR_CLI}`,
        END,
    ].filter(Boolean).join('\n');
    const next = existing ? `${existing}\n${block}\n` : `${block}\n`;
    ensureDir(path.dirname(zprofile));
    const temp = `${zprofile}.${process.pid}.tmp`;
    fs.writeFileSync(temp, next, 'utf8');
    fs.renameSync(temp, zprofile);
}
export async function deployBrewRuntime() {
    const root = projectRoot();
    const macos = loadManifest('macos');
    const target = brewConfigDir();
    const catalog = path.join(root, macos.brewMirrorCatalog || 'configs/macos/brew/mirrors.tsv');
    const helper = path.join(root, 'runtime/brew/mirror-cli.zsh');
    const menuCli = path.join(root, 'runtime/brew/mirror-menu.js');
    const menu = path.join(root, 'src/lib/menu-select.js');
    const width = path.join(root, 'src/lib/string-width.js');
    const tty = path.join(root, 'src/lib/tty-term.js');
    for (const file of [catalog, helper, menuCli, menu, width, tty]) {
        if (!fs.existsSync(file))
            throw new Error(`Homebrew runtime file not found: ${file}`);
    }
    ensureDir(path.join(target, 'lib'));
    step('Deploying Homebrew mirror runtime...');
    const deploys = [
        [catalog, path.join(target, 'mirrors.tsv')],
        [helper, path.join(target, 'mirror-cli.zsh')],
        [menuCli, path.join(target, 'lib/mirror-menu.js')],
        [menu, path.join(target, 'lib/menu-select.js')],
        [width, path.join(target, 'lib/string-width.js')],
        [tty, path.join(target, 'lib/tty-term.js')],
    ];
    for (const [src, dest] of deploys) {
        await copyFileDataOnly(src, dest);
        success(`Deployed ${formatLocalDisplay(dest, homeDir())}`);
    }
    for (const legacy of ['menu.js', 'menu.ts', 'menu-select.ts', 'string-width.ts', 'tty-term.ts', 'menu.mjs', 'menu-select.mjs', 'string-width.mjs', 'tty-term.mjs']) {
        const p = path.join(target, 'lib', legacy);
        try {
            if (fs.existsSync(p))
                fs.unlinkSync(p);
        }
        catch {
            // ignore
        }
    }
    removeBrewMirrorLegacy();
    stepSuccess(`Deployed Homebrew mirror runtime to ${target}`);
}
