import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { formatInitUsage, formatPmUsage, hasMirror, hasProfile, loadManifest, mirrorInstallMode, profileLabel, resolveProfileArtifact, zshPluginsDir, } from "./manifest.js";
describe('manifest', () => {
    const common = loadManifest('common');
    const macos = loadManifest('macos');
    const windows = loadManifest('windows');
    it('resolves profiles', () => {
        assert.equal(hasProfile('lite', common), true);
        assert.equal(hasProfile('full', common), true);
        assert.equal(hasProfile('nope', common), false);
        assert.equal(profileLabel('lite', common), '尝鲜版');
        assert.equal(profileLabel('full', common), '完整版');
        const initUsage = formatInitUsage(common);
        assert.match(initUsage, /vpr init \[lite\|full\]/);
        assert.match(initUsage, /vpr init -- lite/);
        assert.match(initUsage, /vpr init -- full/);
    });
    it('resolves profile artifacts', () => {
        assert.equal(resolveProfileArtifact('macos', 'lite'), macos.brewfileLite);
        assert.equal(resolveProfileArtifact('macos', 'full'), macos.brewfile);
        assert.equal(resolveProfileArtifact('windows', 'lite'), windows.scoopBackupLite);
        assert.equal(resolveProfileArtifact('windows', 'full'), windows.scoopBackup);
        assert.throws(() => resolveProfileArtifact('macos', 'nope'), /profileArtifacts/);
    });
    it('resolves brew mirrors', () => {
        assert.equal(hasMirror('official', macos), true);
        assert.equal(hasMirror('ustc', macos), true);
        assert.equal(hasMirror('tuna', macos), true);
        assert.equal(hasMirror('nope', macos), false);
        const pmUsage = formatPmUsage(macos);
        assert.match(pmUsage, /vpr pm \[ustc\|tuna\|official\]/);
        assert.match(pmUsage, /vpr pm -- ustc/);
        assert.match(pmUsage, /vpr pm -- tuna/);
        assert.match(pmUsage, /vpr pm -- official/);
        assert.match(pmUsage, /中科大镜像/);
        assert.equal(macos.brewMirrorCatalog, 'configs/macos/brew/mirrors.tsv');
        assert.ok(Array.isArray(macos.brewLiteItems) && macos.brewLiteItems.length > 0);
        assert.deepEqual(mirrorInstallMode(macos.brewMirrors.tuna, macos.brewMirrors.official.installScript), { mode: 'git', url: macos.brewMirrors.tuna.installGitRepo });
        assert.deepEqual(mirrorInstallMode(macos.brewMirrors.ustc, macos.brewMirrors.official.installScript), { mode: 'script', url: macos.brewMirrors.ustc.installScript });
        assert.deepEqual(mirrorInstallMode(macos.brewMirrors.official, macos.brewMirrors.official.installScript), { mode: 'script', url: macos.brewMirrors.official.installScript });
        assert.deepEqual(mirrorInstallMode({}, macos.brewMirrors.official.installScript), { mode: 'script', url: macos.brewMirrors.official.installScript });
    });
    it('resolves zsh plugins dir', () => {
        assert.equal(zshPluginsDir(common), '~/.zsh/plugins');
        assert.ok(common.directories.includes(common.zshPluginsDir));
    });
});
