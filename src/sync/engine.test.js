import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { projectRoot } from "../core/paths.js";
import { backupFile, copyFileDataOnly, syncDirectory } from "../core/copy.js";
import { runConfigSync } from "./engine.js";

test('copyFileDataOnly copies bytes and supports utf8Bom', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-copy-'));
    try {
        const src = path.join(root, 'a.txt');
        const dest = path.join(root, 'out', 'a.txt');
        const bomDest = path.join(root, 'out', 'bom.txt');
        fs.writeFileSync(src, 'hello\n');

        await copyFileDataOnly(src, dest);
        assert.equal(fs.readFileSync(dest, 'utf8'), 'hello\n');

        await copyFileDataOnly(src, bomDest, { encoding: 'utf8Bom' });
        const bom = fs.readFileSync(bomDest);
        assert.equal(bom[0], 0xEF);
        assert.equal(bom[1], 0xBB);
        assert.equal(bom[2], 0xBF);
        assert.equal(fs.readFileSync(bomDest, 'utf8').replace(/^\uFEFF/, ''), 'hello\n');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('copyFileDataOnly skips identical content but force re-copies', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-copy-skip-'));
    try {
        const src = path.join(root, 'a.txt');
        const dest = path.join(root, 'out', 'a.txt');
        fs.writeFileSync(src, 'hello\n');
        await copyFileDataOnly(src, dest);
        const firstMtime = fs.statSync(dest).mtimeMs;
        fs.utimesSync(dest, new Date(), new Date(firstMtime - 5000));
        const bumpedMtime = fs.statSync(dest).mtimeMs;
        await copyFileDataOnly(src, dest);
        assert.ok(
            Math.abs(fs.statSync(dest).mtimeMs - bumpedMtime) < 1,
            'identical copy must not touch mtime',
        );
        await copyFileDataOnly(src, dest, { force: true });
        assert.ok(fs.statSync(dest).mtimeMs > bumpedMtime, 'force re-copies');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('copyFileDataOnly utf8Bom skips identical BOM content', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-copy-bom-'));
    try {
        const src = path.join(root, 'a.txt');
        const dest = path.join(root, 'out', 'bom.txt');
        fs.writeFileSync(src, 'hello\n');
        await copyFileDataOnly(src, dest, { encoding: 'utf8Bom' });
        const firstMtime = fs.statSync(dest).mtimeMs;
        await copyFileDataOnly(src, dest, { encoding: 'utf8Bom' });
        assert.ok(Math.abs(fs.statSync(dest).mtimeMs - firstMtime) < 1, 'identical BOM copy must not touch mtime');
        assert.equal(fs.readFileSync(dest, 'utf8'), '\uFEFFhello\n');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('backupFile versions existing locals', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-bak-'));
    try {
        const target = path.join(root, 'settings.json');
        const backupDir = path.join(root, 'backup');
        fs.writeFileSync(target, '{"a":1}\n');
        const first = await backupFile(target, backupDir);
        const second = await backupFile(target, backupDir);
        assert.ok(first);
        assert.ok(second);
        assert.notEqual(first, second);
        assert.equal(fs.readFileSync(path.join(backupDir, first), 'utf8'), '{"a":1}\n');
        assert.equal(await backupFile(path.join(root, 'missing'), backupDir), null);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('runConfigSync backup and restore directions', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-sync-engine-'));
    const prevHome = process.env.HOME;
    const prevUserProfile = process.env.USERPROFILE;
    const repoRel = path.join('.tmp-vpr-sync-test', `run-${process.pid}`, 'configs', 'testrc');
    const repoFile = path.join(projectRoot(), repoRel);
    try {
        const home = path.join(root, 'home');
        fs.mkdirSync(home, { recursive: true });
        process.env.HOME = home;
        process.env.USERPROFILE = home;

        const localFile = path.join(home, '.testrc');
        fs.writeFileSync(localFile, 'from-local\n');

        await runConfigSync({
            platform: 'macos',
            direction: '1',
            fromDispatch: true,
            items: [{ local: '~/.testrc', repo: repoRel, backup: false }],
        });
        assert.equal(fs.readFileSync(repoFile, 'utf8'), 'from-local\n');

        fs.writeFileSync(repoFile, 'from-repo\n');
        fs.writeFileSync(localFile, 'will-be-backed-up\n');
        await runConfigSync({
            platform: 'macos',
            direction: '2',
            fromDispatch: true,
            items: [{ local: '~/.testrc', repo: repoRel, backup: true }],
        });
        assert.equal(fs.readFileSync(localFile, 'utf8'), 'from-repo\n');
        const backups = fs.readdirSync(path.join(home, '.backup'));
        assert.ok(backups.some((name) => name.startsWith('.testrc.bak.')));
    }
    finally {
        if (prevHome === undefined)
            delete process.env.HOME;
        else
            process.env.HOME = prevHome;
        if (prevUserProfile === undefined)
            delete process.env.USERPROFILE;
        else
            process.env.USERPROFILE = prevUserProfile;
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(path.dirname(path.dirname(repoFile)), { recursive: true, force: true });
    }
});

test('runConfigSync mirrors an opencode-style directory and keeps excluded local files', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-sync-dir-'));
    const prevHome = process.env.HOME;
    const prevUserProfile = process.env.USERPROFILE;
    const repoRel = path.join('.tmp-vpr-sync-test', `dir-${process.pid}`, 'opencode');
    const repoDir = path.join(projectRoot(), repoRel);
    const exclude = ['service.json', 'node_modules'];
    try {
        const home = path.join(root, 'home');
        const localDir = path.join(home, '.config', 'opencode');
        fs.mkdirSync(path.join(localDir, 'agents'), { recursive: true });
        fs.mkdirSync(path.join(localDir, 'node_modules', 'pkg'), { recursive: true });
        fs.writeFileSync(path.join(localDir, 'opencode.jsonc'), 'local\n');
        fs.writeFileSync(path.join(localDir, 'agents', 'review.md'), 'review\n');
        fs.writeFileSync(path.join(localDir, 'agents', 'gone.md'), 'gone\n');
        fs.writeFileSync(path.join(localDir, 'service.json'), 'secret\n');
        fs.writeFileSync(path.join(localDir, 'node_modules', 'pkg', 'index.js'), 'x\n');
        process.env.HOME = home;
        process.env.USERPROFILE = home;

        await runConfigSync({
            platform: 'macos',
            direction: '1',
            fromDispatch: true,
            items: [{
                local: '~/.config/opencode',
                repo: repoRel,
                backup: true,
                directory: true,
                exclude,
            }],
        });
        assert.equal(fs.readFileSync(path.join(repoDir, 'opencode.jsonc'), 'utf8'), 'local\n');
        assert.equal(fs.readFileSync(path.join(repoDir, 'agents', 'review.md'), 'utf8'), 'review\n');
        assert.equal(fs.existsSync(path.join(repoDir, 'service.json')), false);
        assert.equal(fs.existsSync(path.join(repoDir, 'node_modules')), false);

        fs.writeFileSync(path.join(repoDir, 'opencode.jsonc'), 'repo\n');
        fs.rmSync(path.join(repoDir, 'agents', 'gone.md'), { force: true });
        fs.writeFileSync(path.join(repoDir, 'agents', 'ui.md'), 'ui\n');
        await runConfigSync({
            platform: 'macos',
            direction: '2',
            fromDispatch: true,
            items: [{
                local: '~/.config/opencode',
                repo: repoRel,
                backup: true,
                directory: true,
                exclude,
            }],
        });
        assert.equal(fs.readFileSync(path.join(localDir, 'opencode.jsonc'), 'utf8'), 'repo\n');
        assert.equal(fs.readFileSync(path.join(localDir, 'agents', 'ui.md'), 'utf8'), 'ui\n');
        assert.equal(fs.existsSync(path.join(localDir, 'agents', 'gone.md')), false);
        assert.equal(fs.readFileSync(path.join(localDir, 'service.json'), 'utf8'), 'secret\n');
        assert.equal(fs.readFileSync(path.join(localDir, 'node_modules', 'pkg', 'index.js'), 'utf8'), 'x\n');
        const backups = fs.readdirSync(path.join(home, '.backup'));
        assert.ok(backups.some((name) => name.startsWith('opencode.bak.')));
    }
    finally {
        if (prevHome === undefined)
            delete process.env.HOME;
        else
            process.env.HOME = prevHome;
        if (prevUserProfile === undefined)
            delete process.env.USERPROFILE;
        else
            process.env.USERPROFILE = prevUserProfile;
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(path.dirname(repoDir), { recursive: true, force: true });
    }
});

test('syncDirectory replaces a destination symlink instead of following it', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-sync-link-'));
    const source = path.join(root, 'src', 'agents');
    const outside = path.join(root, 'outside');
    const dest = path.join(root, 'dest');
    const link = path.join(dest, 'agents');
    try {
        fs.mkdirSync(source, { recursive: true });
        fs.mkdirSync(outside, { recursive: true });
        fs.mkdirSync(dest, { recursive: true });
        fs.writeFileSync(path.join(source, 'a.md'), 'a\n');
        fs.writeFileSync(path.join(outside, 'keep.txt'), 'keep\n');
        fs.symlinkSync(outside, link);
        await syncDirectory(path.join(root, 'src'), dest);
        assert.equal(fs.lstatSync(link).isSymbolicLink(), false);
        assert.equal(fs.readFileSync(path.join(link, 'a.md'), 'utf8'), 'a\n');
        assert.equal(fs.readFileSync(path.join(outside, 'keep.txt'), 'utf8'), 'keep\n');
        assert.equal(fs.existsSync(path.join(outside, 'a.md')), false);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('directory restore stops when its backup fails', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-sync-bak-'));
    const prevHome = process.env.HOME;
    const prevUserProfile = process.env.USERPROFILE;
    const repoRel = path.join('.tmp-vpr-sync-test', `bak-${process.pid}`, 'opencode');
    const repoDir = path.join(projectRoot(), repoRel);
    try {
        const home = path.join(root, 'home');
        const localFile = path.join(home, '.config', 'opencode');
        fs.mkdirSync(path.dirname(localFile), { recursive: true });
        fs.writeFileSync(localFile, 'local-file\n');
        fs.mkdirSync(repoDir, { recursive: true });
        fs.writeFileSync(path.join(repoDir, 'opencode.jsonc'), 'from-repo\n');
        process.env.HOME = home;
        process.env.USERPROFILE = home;
        await assert.rejects(() => runConfigSync({
            platform: 'macos',
            direction: '2',
            fromDispatch: true,
            items: [{
                local: '~/.config/opencode',
                repo: repoRel,
                backup: true,
                directory: true,
                exclude: [],
            }],
        }));
        assert.equal(fs.readFileSync(localFile, 'utf8'), 'local-file\n');
    }
    finally {
        if (prevHome === undefined)
            delete process.env.HOME;
        else
            process.env.HOME = prevHome;
        if (prevUserProfile === undefined)
            delete process.env.USERPROFILE;
        else
            process.env.USERPROFILE = prevUserProfile;
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(path.dirname(repoDir), { recursive: true, force: true });
    }
});
