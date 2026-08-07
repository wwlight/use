import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { projectRoot } from "../core/paths.js";
import { backupFile, copyFileDataOnly } from "./copy.js";
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
