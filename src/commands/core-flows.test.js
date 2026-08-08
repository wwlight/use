import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { resolveZshPluginUpdate } from "./zsh-plugin.js";
import { runGitSetupCommand } from "./git-setup.js";
import { renderBrewLite } from "./backup.js";
import { loadManifest, resolveProfileArtifact } from "../core/manifest.js";
import { projectRoot } from "../core/paths.js";

test('resolveZshPluginUpdate defaults and flags', () => {
    assert.equal(resolveZshPluginUpdate([]), true);
    assert.equal(resolveZshPluginUpdate([], { update: false }), false);
    assert.equal(resolveZshPluginUpdate(['--no-update']), false);
    assert.equal(resolveZshPluginUpdate(['--update'], { update: false }), true);
    assert.equal(resolveZshPluginUpdate(['--', '--no-update']), false);
    assert.throws(() => resolveZshPluginUpdate(['--wat']), /Unknown argument/);
});

test('setup profile artifacts exist', () => {
    const macos = loadManifest('macos');
    const windowsFull = resolveProfileArtifact('windows', 'full');
    assert.ok(macos.brewfile);
    assert.ok(fs.existsSync(path.join(projectRoot(), macos.brewfile)));
    assert.ok(fs.existsSync(path.join(projectRoot(), windowsFull)));
});

test('backup renders lite brewfile from manifest items', () => {
    const root = projectRoot();
    const manifest = loadManifest('macos');
    const full = fs.readFileSync(path.join(root, manifest.brewfile), 'utf8');
    const lite = renderBrewLite(full, manifest);
    assert.deepEqual(lite.missing, []);
    assert.equal(lite.written, manifest.brewLiteItems.length);
    for (const { type, name } of manifest.brewLiteItems) {
        assert.match(lite.content, new RegExp(`^${type} "${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`, 'm'));
    }
    assert.ok(!lite.content.includes('brew "mysql"'));
    assert.ok(!lite.content.includes('cask "google-chrome"'));
});

test('git-setup skips identity when already configured', async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-setup-'));
    const conf = path.join(tmp, 'gitconfig');
    const prev = {
        GIT_CONFIG_GLOBAL: process.env.GIT_CONFIG_GLOBAL,
        GIT_CONFIG_SYSTEM: process.env.GIT_CONFIG_SYSTEM,
        GIT_CONFIG_NOSYSTEM: process.env.GIT_CONFIG_NOSYSTEM,
    };
    try {
        process.env.GIT_CONFIG_GLOBAL = conf;
        process.env.GIT_CONFIG_SYSTEM = path.join(tmp, 'nosystem');
        process.env.GIT_CONFIG_NOSYSTEM = '1';
        fs.writeFileSync(conf, '');
        spawnSync('git', ['config', '--global', 'user.name', 'vpr-test'], { encoding: 'utf8' });
        spawnSync('git', ['config', '--global', 'user.email', 'vpr-test@example.com'], { encoding: 'utf8' });

        const code = await runGitSetupCommand([]);
        assert.equal(code, 0);
        assert.equal(
            spawnSync('git', ['config', '--global', '--get', 'user.name'], { encoding: 'utf8' }).stdout.trim(),
            'vpr-test',
        );
    }
    finally {
        for (const [key, value] of Object.entries(prev)) {
            if (value === undefined)
                delete process.env[key];
            else
                process.env[key] = value;
        }
        fs.rmSync(tmp, { recursive: true, force: true });
    }
});

test('git-setup skips identity prompt in non-interactive mode', async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-setup-ni-'));
    const conf = path.join(tmp, 'gitconfig');
    const prev = {
        GIT_CONFIG_GLOBAL: process.env.GIT_CONFIG_GLOBAL,
        GIT_CONFIG_SYSTEM: process.env.GIT_CONFIG_SYSTEM,
        GIT_CONFIG_NOSYSTEM: process.env.GIT_CONFIG_NOSYSTEM,
    };
    const stdinWasTTY = process.stdin.isTTY;
    try {
        process.env.GIT_CONFIG_GLOBAL = conf;
        process.env.GIT_CONFIG_SYSTEM = path.join(tmp, 'nosystem');
        process.env.GIT_CONFIG_NOSYSTEM = '1';
        fs.writeFileSync(conf, '');
        Object.defineProperty(process.stdin, 'isTTY', { configurable: true, value: false });

        const code = await runGitSetupCommand([]);
        assert.equal(code, 0);
        assert.notEqual(
            spawnSync('git', ['config', '--global', '--get', 'user.name'], { encoding: 'utf8' }).status,
            0,
        );
    }
    finally {
        Object.defineProperty(process.stdin, 'isTTY', { configurable: true, value: stdinWasTTY });
        for (const [key, value] of Object.entries(prev)) {
            if (value === undefined)
                delete process.env[key];
            else
                process.env[key] = value;
        }
        fs.rmSync(tmp, { recursive: true, force: true });
    }
});
