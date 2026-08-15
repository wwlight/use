#!/usr/bin/env node
/**
 * Scoop mirror CLI (~/.config/scoop/mirror/cli.js).
 *
 * Usage:
 *   node cli.js <clean|smudge>              # git filter (stdin/stdout)
 *   node cli.js repair                      # install/refresh download.ps1 hook
 *   node cli.js switch [<name>|official|status]  # switch / status (interactive if omitted)
 *   node cli.js menu <title> <choice>...         # interactive ↑↓ select
 */
import { Buffer } from 'node:buffer'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
const here = path.dirname(fileURLToPath(import.meta.url));
const MARKERS = [
    // Longer legacy marker must be stripped before the shorter current marker.
    {
        begin: Buffer.from('# >>> scoop-mirror-accel'),
        end: Buffer.from('# <<< scoop-mirror-accel'),
    },
    {
        begin: Buffer.from('# >>> scoop-mirror'),
        end: Buffer.from('# <<< scoop-mirror'),
    },
];
// Resolve ~/.config/scoop/mirror/hook.ps1 at runtime (XDG-aware).
const hookSnippet = Buffer.from([
    '',
    '# >>> scoop-mirror',
    '$__scoopCfg = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME \'scoop\' } else { Join-Path $env:USERPROFILE \'.config\\scoop\' }',
    '. (Join-Path $__scoopCfg \'mirror\\hook.ps1\')',
    '# <<< scoop-mirror',
    '',
].join('\n'));
function findByteSequence(bytes, sequence, start = 0) {
    if (sequence.length === 0)
        return start;
    outer: for (let i = start; i <= bytes.length - sequence.length; i++) {
        for (let j = 0; j < sequence.length; j++) {
            if (bytes[i + j] !== sequence[j])
                continue outer;
        }
        return i;
    }
    return -1;
}
function removeOneHook(bytes, begin, end) {
    const beginAt = findByteSequence(bytes, begin);
    if (beginAt < 0)
        return bytes;
    let endAt = findByteSequence(bytes, end, beginAt);
    if (endAt < 0)
        throw new Error('Incomplete Scoop mirror hook markers');
    let start = beginAt;
    if (start > 0 && bytes[start - 1] === 10) {
        start -= 1;
        if (start > 0 && bytes[start - 1] === 13)
            start -= 1;
    }
    endAt += end.length;
    if (endAt < bytes.length && bytes[endAt] === 13)
        endAt += 1;
    if (endAt < bytes.length && bytes[endAt] === 10)
        endAt += 1;
    return Buffer.concat([bytes.subarray(0, start), bytes.subarray(endAt)]);
}
function removeHook(bytes) {
    let current = bytes;
    for (const marker of MARKERS) {
        current = removeOneHook(current, marker.begin, marker.end);
    }
    return current;
}
function addHook(bytes) {
    const currentBegin = Buffer.from('# >>> scoop-mirror');
    if (findByteSequence(bytes, currentBegin) >= 0)
        return bytes;
    return Buffer.concat([removeHook(bytes), hookSnippet]);
}
function buffersEqual(left, right) {
    if (left.length !== right.length)
        return false;
    return left.compare(right) === 0;
}
function legacyLineEndingDamage(current, tracked) {
    const normalize = (buf) => {
        let text = buf.toString('utf8');
        if (text.charCodeAt(0) === 0xfeff)
            text = text.slice(1);
        return text.replace(/\r\n/g, '\n');
    };
    try {
        return normalize(current) === normalize(tracked);
    }
    catch {
        return false;
    }
}
function runGit(repo, args, options = {}) {
    const result = spawnSync('git.exe', ['-C', repo, ...args], {
        encoding: options.encoding ?? 'utf8',
        maxBuffer: options.maxBuffer ?? 32 * 1024 * 1024,
        stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'],
    });
    if (result.error)
        throw result.error;
    return result;
}
function gitBlob(repo, object) {
    const result = runGit(repo, ['cat-file', 'blob', object], {
        encoding: 'buffer',
        stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (result.status !== 0) {
        const err = result.stderr?.toString('utf8') || 'unknown error';
        throw new Error(`Could not read Scoop's tracked download.ps1: ${err}`);
    }
    return Buffer.from(result.stdout);
}
function quoteForGitFilter(filePath) {
    return `"${filePath.replace(/\\/g, '/')}"`;
}
function gitConfigValue(repo, key) {
    const result = runGit(repo, ['config', '--local', '--get', key]);
    if (result.status !== 0)
        return '';
    return String(result.stdout || '').trim();
}
export function hasCurrentHookMarkers(bytes) {
    const begin = Buffer.from('# >>> scoop-mirror');
    const end = Buffer.from('# <<< scoop-mirror');
    let searchFrom = 0;
    while (true) {
        const beginAt = findByteSequence(bytes, begin, searchFrom);
        if (beginAt < 0)
            return false;
        const afterBegin = beginAt + begin.length;
        // Reject `# >>> scoop-mirror-accel` (current begin is a prefix of that marker).
        if (afterBegin < bytes.length && bytes[afterBegin] !== 10 && bytes[afterBegin] !== 13) {
            searchFrom = afterBegin;
            continue;
        }
        const endAt = findByteSequence(bytes, end, afterBegin);
        if (endAt < 0)
            return false;
        const afterEnd = endAt + end.length;
        if (afterEnd < bytes.length && bytes[afterEnd] !== 10 && bytes[afterEnd] !== 13) {
            searchFrom = afterBegin;
            continue;
        }
        const slice = bytes.subarray(beginAt, endAt + end.length).toString('utf8');
        return (
            (slice.includes('mirror\\hook.ps1') || slice.includes('mirror/hook.ps1'))
            && (slice.includes('XDG_CONFIG_HOME') || slice.includes('.config\\scoop') || slice.includes('.config/scoop'))
        );
    }
}
function attributesReady(attributesPath) {
    if (!fs.existsSync(attributesPath))
        return false;
    const lines = fs.readFileSync(attributesPath, 'utf8').split(/\r?\n/);
    return lines.some((line) => /^\s*lib\/download\.ps1\s+filter=scoop-mirror\b/.test(line)
        && !/filter=scoop-mirror-accel\b/.test(line));
}
/** Cheap preflight: skip full rewrite when hook, filter, attributes, and worktree are already healthy. */
function isRepairHealthy({ scoopRepo, download, clean, smudge }) {
    if (!hasCurrentHookMarkers(fs.readFileSync(download)))
        return false;
    if (gitConfigValue(scoopRepo, 'filter.scoop-mirror.clean') !== clean)
        return false;
    if (gitConfigValue(scoopRepo, 'filter.scoop-mirror.smudge') !== smudge)
        return false;
    if (gitConfigValue(scoopRepo, 'filter.scoop-mirror.required') !== 'true')
        return false;
    if (!attributesReady(path.join(scoopRepo, '.git', 'info', 'attributes')))
        return false;
    const status = runGit(scoopRepo, ['status', '--porcelain', '--untracked-files=no']);
    if (status.status !== 0)
        return false;
    return !String(status.stdout || '').trim();
}
function repairHook() {
    const scoop = process.env.SCOOP;
    if (!scoop || !scoop.trim())
        throw new Error('SCOOP environment variable is not set');
    const selfPath = fileURLToPath(import.meta.url);
    const helper = path.join(here, 'hook.ps1');
    const scoopRepo = path.join(scoop, 'apps', 'scoop', 'current');
    const download = path.join(scoopRepo, 'lib', 'download.ps1');
    if (!fs.existsSync(helper))
        throw new Error(`Scoop mirror hook not found: ${helper}`);
    if (!fs.existsSync(path.join(scoopRepo, '.git')))
        throw new Error(`Scoop Git repository not found: ${scoopRepo}`);
    if (!fs.existsSync(download))
        throw new Error(`Scoop download.ps1 not found: ${download}`);
    const nodePath = process.execPath;
    const clean = `${quoteForGitFilter(nodePath)} ${quoteForGitFilter(selfPath)} clean`;
    const smudge = `${quoteForGitFilter(nodePath)} ${quoteForGitFilter(selfPath)} smudge`;
    if (isRepairHealthy({ scoopRepo, download, clean, smudge }))
        return;
    for (const [key, value] of [
        ['filter.scoop-mirror.clean', clean],
        ['filter.scoop-mirror.smudge', smudge],
        ['filter.scoop-mirror.required', 'true'],
    ]) {
        const result = runGit(scoopRepo, ['config', '--local', key, value]);
        if (result.status !== 0)
            throw new Error(`Could not configure ${key}`);
    }
    const attributes = path.join(scoopRepo, '.git', 'info', 'attributes');
    const attributeLine = 'lib/download.ps1 filter=scoop-mirror -text';
    let lines = [];
    if (fs.existsSync(attributes)) {
        lines = fs.readFileSync(attributes, 'utf8')
            .split(/\r?\n/)
            .filter((line) => line.length > 0)
            .filter((line) => !/^\s*lib\/download\.ps1\s+.*filter=scoop-mirror(-accel)?\b/.test(line));
    }
    lines.push(attributeLine);
    fs.mkdirSync(path.dirname(attributes), { recursive: true });
    fs.writeFileSync(attributes, `${lines.join('\n')}\n`, 'utf8');
    const tracked = gitBlob(scoopRepo, ':lib/download.ps1');
    const current = fs.readFileSync(download);
    const currentWithoutHook = removeHook(current);
    if (!buffersEqual(currentWithoutHook, tracked) && !legacyLineEndingDamage(currentWithoutHook, tracked)) {
        throw new Error('Scoop lib/download.ps1 contains changes unrelated to the mirror hook; refusing to overwrite them');
    }
    fs.writeFileSync(download, addHook(tracked));
    const before = runGit(scoopRepo, ['rev-parse', '--verify', ':lib/download.ps1']);
    const indexObjectBefore = String(before.stdout || '').trim();
    if (before.status !== 0 || !indexObjectBefore) {
        throw new Error('Could not read the Scoop download.ps1 index object');
    }
    const refresh = runGit(scoopRepo, ['update-index', '--add', '--', 'lib/download.ps1']);
    const after = runGit(scoopRepo, ['rev-parse', '--verify', ':lib/download.ps1']);
    const indexObjectAfter = String(after.stdout || '').trim();
    if (refresh.status !== 0)
        throw new Error('Could not refresh the Scoop download.ps1 index metadata');
    if (after.status !== 0 || indexObjectAfter !== indexObjectBefore) {
        throw new Error('Scoop download.ps1 index object changed while refreshing metadata');
    }
    const status = runGit(scoopRepo, ['status', '--porcelain', '--untracked-files=no']);
    if (status.status !== 0)
        throw new Error('Could not verify the Scoop Git worktree');
    const dirty = String(status.stdout || '').trim();
    if (dirty) {
        throw new Error(`Scoop has unrelated tracked changes; refusing to start a package operation:\n${dirty}`);
    }
}
async function loadMenuModule() {
    const candidates = [path.join(here, 'lib', 'menu-select.js')];
    let dir = here;
    for (;;) {
        if (fs.existsSync(path.join(dir, 'manifests', 'common.json'))) {
            candidates.push(path.join(dir, 'src', 'lib', 'menu-select.js'));
            break;
        }
        const parent = path.dirname(dir);
        if (parent === dir)
            break;
        dir = parent;
    }
    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            return import(pathToFileURL(candidate).href);
        }
    }
    throw new Error('menu-select.js not found next to mirror/cli.js (re-run vpr pm / sync)');
}
async function loadUrlModule() {
    const candidates = [path.join(here, 'lib', 'mirror-url.js')];
    let dir = here;
    for (;;) {
        if (fs.existsSync(path.join(dir, 'manifests', 'common.json'))) {
            candidates.push(path.join(dir, 'src', 'lib', 'mirror-url.js'));
            break;
        }
        const parent = path.dirname(dir);
        if (parent === dir)
            break;
        dir = parent;
    }
    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            return import(pathToFileURL(candidate).href);
        }
    }
    throw new Error('mirror-url.js not found next to mirror/cli.js (re-run vpr pm / sync)');
}
async function runMenuCli(args) {
    const message = args[0];
    const rawChoices = args.slice(1);
    if (!message || rawChoices.length === 0) {
        console.error('Usage: node cli.js menu <title> <value) description> [value) description ...]');
        process.exit(2);
    }
    const { parseChoice, runMenuSelect } = await loadMenuModule();
    const choices = rawChoices.map(parseChoice);
    const value = await runMenuSelect({
        message,
        choices,
        initialValue: process.env.MENU_SELECT_INITIAL,
    });
    const text = `${String(value).trim()}\n`;
    const outFile = process.env.MENU_SELECT_OUT;
    if (outFile)
        fs.writeFileSync(outFile, text, 'utf8');
    else
        process.stdout.write(text);
}
function loadMirrorConfig(configPath, url) {
    const raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const prefixes = [];
    for (const item of raw.mirrorPrefix || []) {
        const p = url.normalizePrefix(item);
        if (p && !prefixes.includes(p))
            prefixes.push(p);
    }
    let mirrors = (raw.mirrors || [])
        .map((item) => ({
        id: String(item.id || '').trim(),
        prefix: url.normalizePrefix(item.prefix),
    }))
        .filter((item) => item.id && item.prefix);
    if (mirrors.length === 0) {
        mirrors = prefixes.map((prefix) => {
            let id = prefix;
            try {
                id = new URL(prefix).hostname.split('.')[0].replace(/[^A-Za-z0-9]/g, '') || prefix;
            }
            catch { /* keep prefix */ }
            return { id, prefix };
        });
    }
    let activePrefix = '';
    if (Object.prototype.hasOwnProperty.call(raw, 'activePrefix')) {
        activePrefix = url.normalizePrefix(raw.activePrefix);
    }
    else if (prefixes.length > 0) {
        activePrefix = prefixes[0];
    }
    return {
        prefixes,
        mirrors,
        activePrefix,
        githubHosts: [...(raw.githubHosts || [])],
        scoopRepo: String(raw.scoopRepo || '').trim(),
        configPath,
        raw,
    };
}
function buildShellCommandLine(command, args) {
    if (process.platform === 'win32') {
        const quoted = [command, ...args].map((a) => /[\s"]/.test(a) ? `"${a.replace(/"/g, '\\"')}"` : a);
        return quoted.join(' ');
    }
    return [command, ...args].map((a) => (a.includes(' ') ? `'${a.replace(/'/g, "'\\''")}'` : a)).join(' ');
}
function runScoop(args) {
    const result = spawnSync(process.platform === 'win32' ? process.env.ComSpec || 'cmd.exe' : '/bin/sh', [
        ...(process.platform === 'win32' ? ['/d', '/s', '/c'] : ['-c']),
        buildShellCommandLine('scoop', args),
    ], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (result.error)
        throw result.error;
    return result;
}
function getUpstreamRepo(config, url) {
    if (config.scoopRepo)
        return config.scoopRepo;
    const result = runScoop(['config', 'scoop_repo']);
    const repo = String(result.stdout || '').trim();
    if (result.status !== 0 || !repo)
        return 'https://github.com/ScoopInstaller/Scoop';
    return url.stripMirrorPrefix(repo, config.prefixes);
}
function setBucketRemotes(activePrefix, config, url) {
    const scoop = process.env.SCOOP;
    const bucketsRoot = path.join(scoop, 'buckets');
    if (!fs.existsSync(bucketsRoot))
        return;
    for (const entry of fs.readdirSync(bucketsRoot, { withFileTypes: true })) {
        if (!entry.isDirectory())
            continue;
        const bucketPath = path.join(bucketsRoot, entry.name);
        if (!fs.existsSync(path.join(bucketPath, '.git')))
            continue;
        const originResult = runGit(bucketPath, ['remote', 'get-url', 'origin']);
        const origin = String(originResult.stdout || '').trim();
        if (originResult.status !== 0 || !origin)
            continue;
        const bare = url.stripMirrorPrefix(origin, config.prefixes);
        if (!url.isGithubHost(bare, config.githubHosts))
            continue;
        const target = activePrefix ? activePrefix + bare : bare;
        if (target === origin)
            continue;
        const setResult = runGit(bucketPath, ['remote', 'set-url', 'origin', target]);
        if (setResult.status !== 0) {
            throw new Error(`Could not switch bucket '${entry.name}' to ${target}`);
        }
    }
}
function writeActivePrefix(config, activePrefix) {
    const next = { ...config.raw, activePrefix };
    fs.writeFileSync(path.join(here, 'state.json'), `${JSON.stringify(next, null, 2)}\n`, 'utf8');
}
function printMirrorStatus(config, url) {
    const activeId = url.mirrorId(config.activePrefix, config.mirrors);
    const activeLabel = activeId === 'official'
        ? 'official'
        : `${activeId} (${config.activePrefix})`;
    console.log(`Active mirror: ${activeLabel}`);
    const repoResult = runScoop(['config', 'scoop_repo']);
    const repo = String(repoResult.stdout || '').trim();
    if (repoResult.status === 0 && repo)
        console.log(`Scoop repo:    ${repo}`);
    console.log('Download rule: selected mirror -> other mirrors -> official; non-GitHub URLs use direct');
}
function switchMirror(choice, config, url) {
    const activePrefix = url.resolveMirrorChoice(choice, config.mirrors);
    const upstreamRepo = getUpstreamRepo(config, url);
    const repo = activePrefix ? activePrefix + upstreamRepo : upstreamRepo;
    const setRepo = runScoop(['config', 'scoop_repo', repo]);
    if (setRepo.status !== 0) {
        const detail = String(setRepo.stderr || setRepo.stdout || '').trim();
        throw new Error(detail || `Could not set Scoop repo to ${repo}`);
    }
    setBucketRemotes(activePrefix, config, url);
    writeActivePrefix(config, activePrefix);
    printMirrorStatus({ ...config, activePrefix }, url);
}
async function selectMirrorInteractively(config, url) {
    const { formatAlignedChoices, runMenuSelect } = await loadMenuModule();
    const activeId = url.mirrorId(config.activePrefix, config.mirrors);
    const items = [
        ...config.mirrors.map((mirror) => ({
            value: mirror.id,
            name: mirror.id,
            detail: mirror.prefix,
        })),
        {
            value: 'official',
            name: 'official',
            detail: getUpstreamRepo(config, url),
        },
    ];
    return runMenuSelect({
        message: 'Choose a Scoop mirror',
        choices: formatAlignedChoices(items, { activeValue: activeId }),
        initialValue: activeId,
    });
}
async function runSwitchCli(choiceArg) {
    const configPath = path.join(here, 'state.json');
    if (!fs.existsSync(configPath)) {
        throw new Error(`Scoop mirror state not found at ${configPath}`);
    }
    const url = await loadUrlModule();
    const config = loadMirrorConfig(configPath, url);
    let choice = String(choiceArg || '').trim();
    if (['-h', '--help', 'help'].includes(choice)) {
        console.log('Usage: scoop mirror [<name>|official|status]');
        console.log('');
        console.log('  (no args)        interactive select (↑↓ / Enter; Esc or Ctrl+C cancel; Enter on * exits; * = active)');
        console.log('  <name>|official  switch directly');
        console.log('  status           show active mirror');
        return;
    }
    if (choice === 'status') {
        printMirrorStatus(config, url);
        return;
    }
    if (!choice) {
        choice = await selectMirrorInteractively(config, url);
        if (choice === url.mirrorId(config.activePrefix, config.mirrors))
            return;
    }
    switchMirror(choice, config, url);
}
async function readStdin() {
    const chunks = [];
    for await (const chunk of process.stdin)
        chunks.push(chunk);
    return Buffer.concat(chunks);
}
const isMain = process.argv[1]
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
    const mode = process.argv[2];
    try {
        if (mode === 'repair') {
            repairHook();
            process.exit(0);
        }
        if (mode === 'switch') {
            await runSwitchCli(process.argv[3] || '');
            process.exit(0);
        }
        if (mode === 'menu') {
            await runMenuCli(process.argv.slice(3));
            process.exit(0);
        }
        const input = await readStdin();
        let output;
        if (mode === 'clean')
            output = removeHook(input);
        else if (mode === 'smudge')
            output = addHook(input);
        else {
            console.error('Usage: node cli.js <clean|smudge|repair|switch|menu>');
            process.exit(2);
        }
        process.stdout.write(output);
    }
    catch (err) {
        if (err?.code === 'CANCELLED')
            process.exit(130);
        console.error(err?.message || err);
        process.exit(1);
    }
}
