import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';
import { runRepoUpdateCommand, repoUrl } from "./repo-update.js";

function git(cwd, args, opts = {}) {
    const r = spawnSync('git', args, { cwd, encoding: 'utf8', ...opts });
    if (r.status !== 0)
        throw new Error(`git ${args.join(' ')} failed: ${r.stderr || r.stdout}`);
    return (r.stdout || '').trim();
}

function cleanup(root) {
    try {
        fs.rmSync(root, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
    }
    catch {
        // ignore
    }
}

function normalizeEol(text) {
    return String(text).replace(/\r\n/g, '\n');
}

/** Build a remote whose origin is the *local* test repo, mirroring the use repo. */
function makeUseRepo(root) {
    const remote = path.join(root, 'origin.git');
    const work = path.join(root, 'work');
    fs.mkdirSync(work, { recursive: true });
    spawnSync('git', ['init', '--bare', '-b', 'main', remote], { encoding: 'utf8' });
    git(work, ['init', '-b', 'main']);
    git(work, ['config', 'user.email', 'test@example.com']);
    git(work, ['config', 'user.name', 'test']);
    fs.writeFileSync(path.join(work, 'app.txt'), 'v1\n');
    git(work, ['add', '.']);
    git(work, ['commit', '-m', 'v1']);
    git(work, ['remote', 'add', 'origin', remote]);
    git(work, ['push', '-u', 'origin', 'main']);
    return { remote, work, url: pathToFileURL(remote).href };
}

describe('repo-update', () => {
    it('repoUrl is declared in common manifest', () => {
        assert.match(repoUrl(), /^https:\/\/github\.com\//);
    });

    it('updates an existing git checkout in place', async () => {
        const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-repo-update-'));
        try {
            const { remote, work, url } = makeUseRepo(root);
            const checkout = path.join(root, 'checkout');
            git(root, ['clone', url, checkout]);
            assert.equal(normalizeEol(fs.readFileSync(path.join(checkout, 'app.txt'), 'utf8')), 'v1\n');

            // The manifest repo is github.com, but repo-update reads the origin
            // remote, so a local test checkout resolves against it.
            fs.writeFileSync(path.join(work, 'app.txt'), 'v2\n');
            git(work, ['add', '.']);
            git(work, ['commit', '-m', 'v2']);
            git(work, ['push']);
            const remoteHead = git(work, ['rev-parse', 'HEAD']);

            await runRepoUpdateCommand(checkout);
            assert.equal(normalizeEol(fs.readFileSync(path.join(checkout, 'app.txt'), 'utf8')), 'v2\n');
            assert.equal(git(checkout, ['rev-parse', 'HEAD']), remoteHead);
        }
        finally {
            cleanup(root);
        }
    });
});