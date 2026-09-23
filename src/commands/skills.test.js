import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { partitionSkillLock, quoteCmdArg, readSkillLock, runSkillsCommand, skillLockLocal, skillsAddArgs, } from "./skills.js";

const command = { cmd: 'skills', baseArgs: [] };

function writeLock(file, skills) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify({ version: 3, skills }));
}

test('skill lock path comes from the common manifest', () => {
    assert.equal(skillLockLocal(), '~/.agents/.skill-lock.json');
});

test('readSkillLock rejects a missing, invalid, or empty lock', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-skills-lock-'));
    const lock = path.join(root, '.skill-lock.json');
    try {
        assert.throws(() => readSkillLock(lock), /not found/);
        fs.writeFileSync(lock, '{');
        assert.throws(() => readSkillLock(lock), /not valid JSON/);
        fs.writeFileSync(lock, '{"skills":{}}');
        assert.throws(() => readSkillLock(lock), /no skills/);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('partitionSkillLock groups by source and keeps skills with no source', () => {
    const { groups, invalid } = partitionSkillLock({
        archify: { source: 'tt-a1i/archify' },
        teach: { source: 'mattpocock/skills' },
        'grill-me': { source: 'mattpocock/skills' },
        local: {},
    });
    assert.deepEqual(groups, [
        { source: 'tt-a1i/archify', skills: ['archify'] },
        { source: 'mattpocock/skills', skills: ['teach', 'grill-me'] },
    ]);
    assert.deepEqual(invalid, ['local']);
});

test('quoteCmdArg keeps shell metacharacters inside quotes', () => {
    assert.equal(quoteCmdArg('a&b%c'), '"a&b%%c"');
});

test('runSkillsCommand installs each source and removes unlocked directories', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-skills-run-'));
    const skillsDir = path.join(root, 'skills');
    const lock = path.join(root, '.skill-lock.json');
    try {
        writeLock(lock, {
            archify: { source: 'tt-a1i/archify' },
            teach: { source: 'mattpocock/skills' },
            'grill-me': { source: 'mattpocock/skills' },
        });
        fs.mkdirSync(path.join(skillsDir, 'archify'), { recursive: true });
        fs.mkdirSync(path.join(skillsDir, 'stale'), { recursive: true });
        fs.mkdirSync(path.join(skillsDir, '.cache'), { recursive: true });
        const calls = [];
        const code = await runSkillsCommand([], {
            lockPath: lock,
            skillsDir,
            command,
            probe: async () => true,
            run: (cmd, args) => {
                calls.push([cmd, args]);
                return true;
            },
        });
        assert.equal(code, 0);
        assert.equal(fs.existsSync(path.join(skillsDir, 'stale')), false);
        assert.equal(fs.existsSync(path.join(skillsDir, '.cache')), true);
        assert.deepEqual(calls, [
            ['skills', skillsAddArgs('tt-a1i/archify', ['archify'])],
            ['skills', skillsAddArgs('mattpocock/skills', ['teach', 'grill-me'])],
        ]);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('runSkillsCommand does not prune until install can start, and restores a wiped skill', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-skills-fail-'));
    const skillsDir = path.join(root, 'skills');
    const lock = path.join(root, '.skill-lock.json');
    const extra = path.join(skillsDir, 'extra');
    const marker = path.join(skillsDir, 'two', 'SKILL.md');
    try {
        fs.mkdirSync(extra, { recursive: true });
        fs.writeFileSync(lock, '{"skills":{}}');
        assert.equal(await runSkillsCommand([], { lockPath: lock, skillsDir, command, probe: async () => true, run: () => true }), 1);
        assert.equal(fs.existsSync(extra), true);

        writeLock(lock, { one: { source: 'a/one' } });
        let called = false;
        assert.equal(await runSkillsCommand([], {
            lockPath: lock,
            skillsDir,
            command,
            probe: async () => false,
            run: () => {
                called = true;
                return true;
            },
        }), 1);
        assert.equal(called, false);
        assert.equal(fs.existsSync(extra), true);

        writeLock(lock, { one: { source: 'a/one' }, two: { source: 'b/two' } });
        fs.mkdirSync(path.dirname(marker), { recursive: true });
        fs.writeFileSync(marker, 'keep\n');
        const code = await runSkillsCommand([], {
            lockPath: lock,
            skillsDir,
            command,
            probe: async () => true,
            run: (_cmd, args) => {
                if (args[1] !== 'b/two')
                    return true;
                fs.rmSync(path.dirname(marker), { recursive: true, force: true });
                return false;
            },
        });
        assert.equal(code, 1);
        assert.equal(fs.existsSync(extra), false);
        assert.equal(fs.readFileSync(marker, 'utf8'), 'keep\n');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});
