import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { projectRoot } from "../core/paths.js";
import { listBrewMirrors, renderBrewLite, renderBrewMirrorCatalog, } from "./brew.js";
describe('brew generate', () => {
    const root = projectRoot();
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'));
    const full = fs.readFileSync(path.join(root, manifest.brewfile), 'utf8');
    it('renders catalog mirrors', () => {
        const mirrors = listBrewMirrors(manifest);
        assert.deepEqual(mirrors.map(({ id }) => id), ['ustc', 'tuna', 'official']);
        assert.match(renderBrewMirrorCatalog(manifest), /^# use-homebrew-mirrors-v1\n/);
        assert.match(renderBrewMirrorCatalog(manifest), /^official\t官方源\t-\t-\t-$/m);
        assert.throws(() => renderBrewMirrorCatalog({
            brewMirrors: { bad: { label: 'Bad', apiDomain: 'http://insecure.test' } },
        }), /https/);
    });
    it('renders lite brewfile from manifest items', () => {
        const lite = renderBrewLite(full, manifest);
        assert.deepEqual(lite.missing, []);
        assert.equal(lite.written, manifest.brewLiteItems.length);
        for (const { type, name } of manifest.brewLiteItems) {
            assert.match(lite.content, new RegExp(`^${type} "${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`, 'm'));
        }
        assert.ok(!lite.content.includes('brew "mysql"'));
        assert.ok(!lite.content.includes('cask "google-chrome"'));
    });
    it('includes required taps for namespaced formulas', () => {
        const tapped = renderBrewLite('tap "owner/tap", trusted: true\nbrew "owner/tap/tool"\nbrew "other"\n', { brewLiteItems: [{ type: 'brew', name: 'owner/tap/tool' }] });
        assert.match(tapped.content, /tap "owner\/tap"/);
        assert.match(tapped.content, /brew "owner\/tap\/tool"/);
        assert.ok(!tapped.content.includes('brew "other"'));
    });
});
