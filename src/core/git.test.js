import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { githubRepoCandidates, isGitRepo, syncGitRepoPlugin } from "./git.js";
import { loadManifest } from "./manifest.js";

function normalizeEol(text) {
    return String(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function git(cwd, args, opts = {}) {
    const r = spawnSync('git', args, { cwd, encoding: 'utf8', ...opts });
    if (r.status !== 0) {
        throw new Error(`git ${args.join(' ')} failed: ${r.stderr || r.stdout}`);
    }
    return (r.stdout || '').trim();
}

function makeRemoteRepo(root, name = 'remote') {
    const remote = path.join(root, `${name}.git`);
    const work = path.join(root, `${name}-work`);
    fs.mkdirSync(work, { recursive: true });
    spawnSync('git', ['init', '--bare', '-b', 'main', remote], { encoding: 'utf8' });
    git(work, ['init', '-b', 'main']);
    git(work, ['config', 'user.email', 'test@example.com']);
    git(work, ['config', 'user.name', 'test']);
    fs.writeFileSync(path.join(work, 'plugin.txt'), 'v1\n');
    git(work, ['add', '.']);
    git(work, ['commit', '-m', 'v1']);
    git(work, ['remote', 'add', 'origin', remote]);
    git(work, ['push', '-u', 'origin', 'main']);
    return { remote: pathToFileURL(remote).href, remotePath: remote, work };
}

function readPlugin(dir) {
    return normalizeEol(fs.readFileSync(path.join(dir, 'plugin.txt'), 'utf8'));
}

function head(dir) {
    return git(dir, ['rev-parse', 'HEAD']);
}

function cleanupTemp(root) {
    try {
        fs.rmSync(root, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
    }
    catch {
        // Windows sometimes holds locks on .git temps; ignore cleanup failures.
    }
}

function isSameOrigin(dir, remotePath) {
    const url = git(dir, ['remote', 'get-url', 'origin']);
    const norm = (u) => {
        try {
            if (String(u).startsWith('file:'))
                return path.resolve(fileURLToPath(u));
        }
        catch {
            // fall through
        }
        return path.resolve(String(u).replace(/^file:\/\//, '').replace(/\/$/, ''));
    };
    return norm(url) === norm(remotePath);
}

test('githubRepoCandidates: selected → other mirrors → official', () => {
    const repo = 'https://github.com/example/demo.git';
    const common = loadManifest('common');
    const mirrors = common.githubAccel?.mirrors ?? [];
    assert.ok(mirrors.length >= 2, 'fixture expects at least two githubAccel mirrors');

    const prev = process.env.USE_ACCEL;
    try {
        const secondary = mirrors.find((m) => m.id !== common.githubAccel.default) || mirrors[1];
        process.env.USE_ACCEL = secondary.id;
        const candidates = githubRepoCandidates(repo);
        assert.deepEqual(candidates, [
            `${secondary.prefix}${repo}`,
            ...mirrors.filter((m) => m.id !== secondary.id).map((m) => `${m.prefix}${repo}`),
            repo,
        ]);

        delete process.env.USE_ACCEL;
        const defaultId = common.githubAccel.default;
        const preferred = mirrors.find((m) => m.id === defaultId) || mirrors[0];
        assert.deepEqual(githubRepoCandidates(repo), [
            `${preferred.prefix}${repo}`,
            ...mirrors.filter((m) => m.id !== preferred.id).map((m) => `${m.prefix}${repo}`),
            repo,
        ]);

        assert.deepEqual(githubRepoCandidates('git@github.com:example/demo.git'), [
            'git@github.com:example/demo.git',
        ]);
    }
    finally {
        if (prev === undefined)
            delete process.env.USE_ACCEL;
        else
            process.env.USE_ACCEL = prev;
    }
});

test('init path: missing installs, existing skips', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-init-'));
    try {
        const { remote, work } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');

        await syncGitRepoPlugin(remote, plugin, 'demo', false);
        assert.equal(isGitRepo(plugin), true);
        assert.equal(readPlugin(plugin), 'v1\n');
        const sha = head(plugin);

        fs.writeFileSync(path.join(work, 'plugin.txt'), 'v2\n');
        git(work, ['add', '.']);
        git(work, ['commit', '-m', 'v2']);
        git(work, ['push']);

        await syncGitRepoPlugin(remote, plugin, 'demo', false);
        assert.equal(head(plugin), sha, 'init skip must not advance existing install');
        assert.equal(readPlugin(plugin), 'v1\n');
    }
    finally {
        cleanupTemp(root);
    }
});

test('zsh-plugin path: matching git repo fetches latest', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-update-'));
    try {
        const { remote, work } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');

        await syncGitRepoPlugin(remote, plugin, 'demo', true);
        const sha1 = head(plugin);

        fs.writeFileSync(path.join(work, 'plugin.txt'), 'v2\n');
        git(work, ['add', '.']);
        git(work, ['commit', '-m', 'v2']);
        git(work, ['push']);
        const remoteHead = git(work, ['rev-parse', 'HEAD']);

        await syncGitRepoPlugin(remote, plugin, 'demo', true);
        assert.equal(head(plugin), remoteHead);
        assert.notEqual(head(plugin), sha1);
        assert.equal(readPlugin(plugin), 'v2\n');
    }
    finally {
        cleanupTemp(root);
    }
});

test('zsh-plugin path: non-git dir reinstalls via temp replace', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-nongit-'));
    try {
        const { remote } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');
        fs.mkdirSync(plugin);
        fs.writeFileSync(path.join(plugin, 'stale.txt'), 'keep-me-if-clone-fails\n');

        await syncGitRepoPlugin(remote, plugin, 'demo', true);
        assert.equal(isGitRepo(plugin), true);
        assert.equal(readPlugin(plugin), 'v1\n');
        assert.equal(fs.existsSync(path.join(plugin, 'stale.txt')), false);
    }
    finally {
        cleanupTemp(root);
    }
});

test('zsh-plugin path: wrong remote reinstalls to expected repo', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-remote-'));
    try {
        const expected = makeRemoteRepo(root, 'expected');
        const other = makeRemoteRepo(root, 'other');
        const plugin = path.join(root, 'plugin');

        await syncGitRepoPlugin(other.remote, plugin, 'demo', true);
        assert.equal(readPlugin(plugin), 'v1\n');

        fs.writeFileSync(path.join(expected.work, 'plugin.txt'), 'expected-latest\n');
        git(expected.work, ['add', '.']);
        git(expected.work, ['commit', '-m', 'expected']);
        git(expected.work, ['push']);

        await syncGitRepoPlugin(expected.remote, plugin, 'demo', true);
        assert.equal(readPlugin(plugin), 'expected-latest\n');
        assert.equal(isSameOrigin(plugin, expected.remotePath), true);
    }
    finally {
        cleanupTemp(root);
    }
});

test('failed reinstall keeps original non-git directory', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-keep-'));
    try {
        const plugin = path.join(root, 'plugin');
        fs.mkdirSync(plugin);
        fs.writeFileSync(path.join(plugin, 'stale.txt'), 'original\n');

        await assert.rejects(
            () => syncGitRepoPlugin('file:///no/such/repo.git', plugin, 'demo', true),
            /Failed to install plugin/,
        );
        assert.equal(fs.existsSync(path.join(plugin, 'stale.txt')), true);
        assert.equal(normalizeEol(fs.readFileSync(path.join(plugin, 'stale.txt'), 'utf8')), 'original\n');
        assert.equal(isGitRepo(plugin), false);
    }
    finally {
        cleanupTemp(root);
    }
});
