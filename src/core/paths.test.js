import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import path from 'node:path';
import { expandPath, formatLocalDisplay, formatRepoDisplay, projectRoot } from "../core/paths.js";
test('expandPath expands home and placeholders', () => {
    const home = '/Users/demo';
    assert.equal(expandPath('~', { home }), home);
    assert.equal(expandPath('~/.zshrc', { home }), `${home}/.zshrc`);
    assert.equal(expandPath('{scoopDir}/config/hook.ps1', {
        home,
        scoopDir: 'D:/SoftwareApps/Scoop',
    }).replace(/\\/g, '/'), 'D:/SoftwareApps/Scoop/config/hook.ps1');
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
