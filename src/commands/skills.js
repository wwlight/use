import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { error, note, step, success, warn } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { expandPath, homeDir } from "../core/paths.js";
import { isHelpFlag, stripDashArgs } from "../core/args.js";

/** Manifest pair whose local path is the global skills lock. */
const LOCK_REPO = 'configs/common/agents/skill-lock.json';
/** Global install target whose skills directory is ~/.agents/skills. */
const SKILL_AGENT = 'cline';

export function formatSkillsUsage() {
    return [
        'Usage: vpr skills',
        '',
        'Install the latest global skills from ~/.agents/.skill-lock.json',
        'and remove ~/.agents/skills directories that are not in the lock.',
        '',
        'Examples:',
        '  vpr skills',
    ].join('\n');
}

export function skillLockLocal() {
    const item = (loadManifest('common').sync?.toRepo ?? []).find((entry) => entry.repo === LOCK_REPO);
    if (!item?.local)
        throw new Error(`common manifest is missing ${LOCK_REPO}`);
    return item.local;
}

export function readSkillLock(lockPath) {
    let raw;
    try {
        raw = fs.readFileSync(lockPath, 'utf8');
    }
    catch (err) {
        if (err?.code === 'ENOENT')
            throw new Error(`Skill lock not found: ${lockPath}`);
        throw err;
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    }
    catch {
        throw new Error(`Skill lock is not valid JSON: ${lockPath}`);
    }
    const skills = parsed?.skills;
    if (!skills || typeof skills !== 'object' || Array.isArray(skills))
        throw new Error(`Skill lock is missing a skills object: ${lockPath}`);
    if (Object.keys(skills).length === 0)
        throw new Error(`Skill lock has no skills: ${lockPath}`);
    return skills;
}

/** Keep lock order. Skills with no source stay in the lock but are not installed. */
export function partitionSkillLock(skills) {
    const groups = [];
    const bySource = new Map();
    const invalid = [];
    for (const [name, entry] of Object.entries(skills)) {
        const source = typeof entry?.source === 'string' ? entry.source.trim() : '';
        if (!source) {
            invalid.push(name);
            continue;
        }
        let group = bySource.get(source);
        if (!group) {
            group = { source, skills: [] };
            bySource.set(source, group);
            groups.push(group);
        }
        group.skills.push(name);
    }
    return { groups, invalid };
}

export function skillsAddArgs(source, skillNames, agent = SKILL_AGENT) {
    return ['add', source, '-g', '-y', '--agent', agent, '--skill', ...skillNames];
}

/** Quote one cmd.exe argument. `&`, `|`, and `%` stay inside the quotes. */
export function quoteCmdArg(arg) {
    return `"${String(arg).replace(/"/g, '""').replace(/%/g, '%%')}"`;
}

export function resolveSkillsCommand() {
    const finder = process.platform === 'win32' ? 'where.exe' : 'which';
    const found = spawnSync(finder, ['skills'], { encoding: 'utf8' });
    const bin = found.status === 0
        ? found.stdout.split(/\r?\n/).map((line) => line.trim()).find(Boolean)
        : '';
    if (bin)
        return { cmd: bin, baseArgs: [] };
    return {
        cmd: process.platform === 'win32' ? 'npx.cmd' : 'npx',
        baseArgs: ['--yes', 'skills'],
    };
}

export function listExtraSkillDirs(skillsDir, wanted) {
    if (!fs.existsSync(skillsDir))
        return [];
    const extras = [];
    for (const entry of fs.readdirSync(skillsDir, { withFileTypes: true })) {
        if (!entry.isDirectory() || entry.name.startsWith('.'))
            continue;
        if (!wanted.has(entry.name))
            extras.push(entry.name);
    }
    return extras;
}

function removeSkillDir(skillsDir, name) {
    const root = path.resolve(skillsDir);
    const target = path.resolve(root, name);
    const rel = path.relative(root, target);
    if (!rel || rel.startsWith('..') || path.isAbsolute(rel))
        throw new Error(`Refusing to remove ${target}`);
    fs.rmSync(target, { recursive: true, force: true });
}

function snapshotSkills(skillsDir, names) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-skills-bak-'));
    const saved = [];
    for (const name of names) {
        const src = path.join(skillsDir, name);
        if (!fs.existsSync(src))
            continue;
        fs.cpSync(src, path.join(root, name), { recursive: true });
        saved.push(name);
    }
    return { root, saved };
}

function restoreSnapshot(skillsDir, snap) {
    for (const name of snap.saved) {
        const dest = path.join(skillsDir, name);
        fs.rmSync(dest, { recursive: true, force: true });
        fs.cpSync(path.join(snap.root, name), dest, { recursive: true });
    }
    fs.rmSync(snap.root, { recursive: true, force: true });
}

function spawnCommand(cmd, args) {
    return new Promise((resolve) => {
        const child = process.platform === 'win32'
            ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/c', [cmd, ...args].map(quoteCmdArg).join(' ')], {
                stdio: 'inherit',
                windowsHide: true,
                windowsVerbatimArguments: true,
            })
            : spawn(cmd, args, { stdio: 'inherit', shell: false, env: process.env });
        child.on('error', () => resolve(false));
        child.on('close', (code) => resolve(code === 0));
    });
}

export async function runSkillsCommand(args = [], options = {}) {
    const clean = stripDashArgs(args);
    if (isHelpFlag(clean)) {
        console.log(formatSkillsUsage());
        return 0;
    }
    if (clean.length > 0)
        throw new Error(`Unknown argument: ${clean[0]}`);

    const home = options.home ?? homeDir();
    const lockPath = options.lockPath ?? expandPath(skillLockLocal(), { home });
    const skillsDir = options.skillsDir ?? path.join(path.dirname(lockPath), 'skills');
    const command = options.command ?? resolveSkillsCommand();
    const run = options.run ?? spawnCommand;

    let skills;
    try {
        skills = readSkillLock(lockPath);
    }
    catch (err) {
        error(err.message);
        return 1;
    }

    const probe = options.probe ?? (() => run(command.cmd, [...command.baseArgs, '--version']));
    if (!await probe()) {
        error('skills CLI is not available');
        return 1;
    }

    step('Syncing global skills from the lock...');
    const wanted = new Set(Object.keys(skills));
    const removed = listExtraSkillDirs(skillsDir, wanted);
    for (const name of removed) {
        removeSkillDir(skillsDir, name);
        note(`Removed extra skill ${name}`);
    }

    const { groups, invalid } = partitionSkillLock(skills);
    for (const name of invalid)
        warn(`Skill ${name} has no source; left in place`);

    const failed = [...invalid];
    let installed = 0;
    for (const group of groups) {
        note(`Installing ${group.skills.join(', ')} from ${group.source}`);
        const args = [...command.baseArgs, ...skillsAddArgs(group.source, group.skills)];
        const snap = snapshotSkills(skillsDir, group.skills);
        let ok = false;
        try {
            ok = await run(command.cmd, args);
        }
        finally {
            if (ok)
                fs.rmSync(snap.root, { recursive: true, force: true });
            else
                restoreSnapshot(skillsDir, snap);
        }
        if (ok)
            installed += group.skills.length;
        else {
            failed.push(group.source);
            warn(`Failed to install skills from ${group.source}`);
        }
    }

    const removedText = removed.length === 0 ? '' : `, removed ${removed.length}`;
    if (failed.length > 0) {
        error(`Installed ${installed} skills${removedText}; failed: ${failed.join(', ')}`);
        return 1;
    }
    success(`Installed ${installed} skills${removedText}`);
    return 0;
}
