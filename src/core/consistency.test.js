import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { projectRoot } from "../core/paths.js";
import { loadManifest } from "../core/manifest.js";

const root = projectRoot();
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

/** Parse `GIT_HTTP_LOW_SPEED_LIMIT` / `GIT_HTTP_LOW_SPEED_TIME` from a file. */
function lowSpeedConstants(text) {
    const limit = text.match(/GIT_HTTP_LOW_SPEED_LIMIT\s*=\s*'?(\d+)'?/)?.[1];
    const time = text.match(/GIT_HTTP_LOW_SPEED_TIME\s*=\s*'?(\d+)'?/)?.[1];
    return { limit, time };
}

/** Parse quoted string literals between two marker lines. */
function blockStrings(text, start, end) {
    const begin = text.indexOf(start);
    const endIdx = text.indexOf(end, begin + start.length);
    if (begin < 0 || endIdx < 0)
        return null;
    const body = text.slice(begin + start.length, endIdx);
    return [...body.matchAll(/['"]([^'"]+)['"]/g)].map((m) => m[1]);
}

describe('cross-language consistency', () => {
    it('GIT_HTTP_LOW_SPEED constants match across install scripts and git.js', () => {
        const sh = lowSpeedConstants(read('install.sh'));
        const ps = lowSpeedConstants(read('install.ps1'));
        const gitJs = fs.readFileSync(path.join(root, 'src/core/git.js'), 'utf8');
        const jsLimit = gitJs.match(/GIT_HTTP_LOW_SPEED_LIMIT = '(\d+)'/)?.[1];
        const jsTime = gitJs.match(/GIT_HTTP_LOW_SPEED_TIME = '(\d+)'/)?.[1];
        assert.deepEqual(
            { limit: sh.limit, time: sh.time },
            { limit: ps.limit, time: ps.time },
            'install.sh and install.ps1 must agree on git low-speed constants',
        );
        assert.deepEqual(
            { limit: sh.limit, time: sh.time },
            { limit: jsLimit, time: jsTime },
            'install scripts and src/core/git.js must agree on git low-speed constants',
        );
    });

    it('github-accel mirror ids/prefixes match manifests/common.json', () => {
        const common = loadManifest('common');
        const expected = common.githubAccel.mirrors.map(({ id, prefix }) => ({
            id,
            prefix: prefix.endsWith('/') ? prefix : `${prefix}/`,
        }));

        const shIds = blockStrings(read('install.sh'), '# BEGIN GENERATED GITHUB ACCEL', '# END GENERATED GITHUB ACCEL')
            .filter((s) => !s.includes('http'));
        const shPrefixes = blockStrings(read('install.sh'), '# BEGIN GENERATED GITHUB ACCEL', '# END GENERATED GITHUB ACCEL')
            .filter((s) => s.includes('http'));
        assert.deepEqual(shIds, expected.map((m) => m.id), 'install.sh accel ids');
        assert.deepEqual(shPrefixes, expected.map((m) => m.prefix), 'install.sh accel prefixes');

        const psIds = blockStrings(read('install.ps1'), '# BEGIN GENERATED GITHUB ACCEL', '# END GENERATED GITHUB ACCEL')
            .filter((s) => !s.includes('http'));
        const psPrefixes = blockStrings(read('install.ps1'), '# BEGIN GENERATED GITHUB ACCEL', '# END GENERATED GITHUB ACCEL')
            .filter((s) => s.includes('http'));
        assert.deepEqual(psIds, expected.map((m) => m.id), 'install.ps1 accel ids');
        assert.deepEqual(psPrefixes, expected.map((m) => m.prefix), 'install.ps1 accel prefixes');
    });

    it('github-accel zsh config matches manifests/common.json', () => {
        const common = loadManifest('common');
        const expected = common.githubAccel.mirrors.map(({ prefix }) => (
            prefix.endsWith('/') ? prefix : `${prefix}/`
        ));
        const zsh = read('configs/common/github-accel.zsh');
        const markerStart = zsh.indexOf('# BEGIN GENERATED GITHUB ACCEL');
        const markerEnd = zsh.indexOf('# END GENERATED GITHUB ACCEL');
        assert.ok(markerStart >= 0 && markerEnd > markerStart, 'github-accel.zsh markers present');
        const body = zsh.slice(markerStart, markerEnd);
        const found = [...body.matchAll(/['"]([^'"]+)['"]/g)].map((m) => m[1]);
        assert.deepEqual(found, expected, 'github-accel.zsh prefixes');
    });

    it('scoop backup lite names match windows manifest scoopLiteApps', () => {
        const win = loadManifest('windows');
        const lite = JSON.parse(read(win.scoopBackupLite));
        const names = (lite.apps || []).map((app) => app.Name).sort();
        assert.deepEqual(names, [...win.scoopLiteApps].sort(), 'scoop lite backup app list');
    });
});