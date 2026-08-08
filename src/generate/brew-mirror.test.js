import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { projectRoot } from "../core/paths.js";
import { checkBrewMirrorGenerated, listBrewMirrors, renderBrewMirrorCatalog, } from "./brew-mirror.js";

describe('brew-mirror', () => {
    const root = projectRoot();
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'));
    it('renders catalog mirrors', () => {
        const mirrors = listBrewMirrors(manifest);
        assert.deepEqual(mirrors.map(({ id }) => id), ['ustc', 'tuna', 'official']);
        assert.match(renderBrewMirrorCatalog(manifest), /^# use-homebrew-mirrors-v1\n/);
        assert.match(renderBrewMirrorCatalog(manifest), /^official\t官方源\t-\t-\t-$/m);
        assert.throws(() => renderBrewMirrorCatalog({
            brewMirrors: { bad: { label: 'Bad', apiDomain: 'http://insecure.test' } },
        }), /https/);
    });
    it('keeps on-disk brew catalog current', () => {
        assert.deepEqual(checkBrewMirrorGenerated(root), { ok: true });
    });
});
