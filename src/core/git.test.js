import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { isGitRepo, syncGitRepoPlugin } from "./git.js";

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
    return { remote: `file://${remote}`, remotePath: remote, work };
}

function readPlugin(dir) {
    return fs.readFileSync(path.join(dir, 'plugin.txt'), 'utf8');
}

function head(dir) {
    return git(dir, ['rev-parse', 'HEAD']);
}

test('init path: missing installs, existing skips', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-init-'));
    try {
        const { remote, work } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');

        syncGitRepoPlugin(remote, plugin, 'demo', false);
        assert.equal(isGitRepo(plugin), true);
        assert.equal(readPlugin(plugin), 'v1\n');
        const sha = head(plugin);

        fs.writeFileSync(path.join(work, 'plugin.txt'), 'v2\n');
        git(work, ['add', '.']);
        git(work, ['commit', '-m', 'v2']);
        git(work, ['push']);

        syncGitRepoPlugin(remote, plugin, 'demo', false);
        assert.equal(head(plugin), sha, 'init skip must not advance existing install');
        assert.equal(readPlugin(plugin), 'v1\n');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('zsh-plugin path: matching git repo fetches latest', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-update-'));
    try {
        const { remote, work } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');

        syncGitRepoPlugin(remote, plugin, 'demo', true);
        const sha1 = head(plugin);

        fs.writeFileSync(path.join(work, 'plugin.txt'), 'v2\n');
        git(work, ['add', '.']);
        git(work, ['commit', '-m', 'v2']);
        git(work, ['push']);
        const remoteHead = git(work, ['rev-parse', 'HEAD']);

        syncGitRepoPlugin(remote, plugin, 'demo', true);
        assert.equal(head(plugin), remoteHead);
        assert.notEqual(head(plugin), sha1);
        assert.equal(readPlugin(plugin), 'v2\n');
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('zsh-plugin path: non-git dir reinstalls via temp replace', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-nongit-'));
    try {
        const { remote } = makeRemoteRepo(root);
        const plugin = path.join(root, 'plugin');
        fs.mkdirSync(plugin);
        fs.writeFileSync(path.join(plugin, 'stale.txt'), 'keep-me-if-clone-fails\n');

        syncGitRepoPlugin(remote, plugin, 'demo', true);
        assert.equal(isGitRepo(plugin), true);
        assert.equal(readPlugin(plugin), 'v1\n');
        assert.equal(fs.existsSync(path.join(plugin, 'stale.txt')), false);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('zsh-plugin path: wrong remote reinstalls to expected repo', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-remote-'));
    try {
        const expected = makeRemoteRepo(root, 'expected');
        const other = makeRemoteRepo(root, 'other');
        const plugin = path.join(root, 'plugin');

        syncGitRepoPlugin(other.remote, plugin, 'demo', true);
        assert.equal(readPlugin(plugin), 'v1\n');

        fs.writeFileSync(path.join(expected.work, 'plugin.txt'), 'expected-latest\n');
        git(expected.work, ['add', '.']);
        git(expected.work, ['commit', '-m', 'expected']);
        git(expected.work, ['push']);

        syncGitRepoPlugin(expected.remote, plugin, 'demo', true);
        assert.equal(readPlugin(plugin), 'expected-latest\n');
        assert.equal(isSameOrigin(plugin, expected.remotePath), true);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('failed reinstall keeps original non-git directory', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-git-keep-'));
    try {
        const plugin = path.join(root, 'plugin');
        fs.mkdirSync(plugin);
        fs.writeFileSync(path.join(plugin, 'stale.txt'), 'original\n');

        assert.throws(
            () => syncGitRepoPlugin('file:///no/such/repo.git', plugin, 'demo', true),
            /Failed to install plugin/,
        );
        assert.equal(fs.existsSync(path.join(plugin, 'stale.txt')), true);
        assert.equal(fs.readFileSync(path.join(plugin, 'stale.txt'), 'utf8'), 'original\n');
        assert.equal(isGitRepo(plugin), false);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

function isSameOrigin(dir, remotePath) {
    const url = git(dir, ['remote', 'get-url', 'origin']);
    const norm = (u) => u.replace(/^file:\/\//, '').replace(/\/$/, '');
    return norm(url) === norm(remotePath);
}
