import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { expandPath, formatLocalDisplay, formatRepoDisplay, projectRoot } from "../core/paths.js";

test('expandPath expands home and placeholders', () => {
    const home = path.join(path.sep === '\\' ? 'C:\\Users' : '/Users', 'demo');
    assert.equal(expandPath('~', { home }), home);
    assert.equal(expandPath('~/.zshrc', { home }), path.join(home, '.zshrc'));
    assert.equal(expandPath('{scoopDir}/config/hook.ps1', {
        home,
        scoopDir: 'D:/SoftwareApps/Scoop',
    }).replace(/\\/g, '/'), 'D:/SoftwareApps/Scoop/config/hook.ps1');
    assert.equal(expandPath('{scoopConfigDir}/mirror/cli.js', {
        home,
        scoopConfigDir: path.join(home, '.config', 'scoop'),
    }).replace(/\\/g, '/'), `${home.replace(/\\/g, '/')}/.config/scoop/mirror/cli.js`);
});

test('format helpers', () => {
    assert.equal(formatRepoDisplay('configs/a'), './configs/a');
    assert.equal(formatRepoDisplay('./configs/a'), './configs/a');
    assert.equal(formatLocalDisplay('/Users/demo/.zshrc', '/Users/demo'), '~/.zshrc');
});

test('projectRoot finds manifests/common.json', () => {
    const root = projectRoot();
    assert.ok(path.isAbsolute(root));
    assert.ok(fs.existsSync(path.join(root, 'manifests', 'common.json')));
    assert.ok(fs.existsSync(path.join(root, 'src', 'lib', 'menu-select.js')));
});
