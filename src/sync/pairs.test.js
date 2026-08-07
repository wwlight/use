import assert from 'node:assert/strict';
import test from 'node:test';
import { readSyncPairLines } from "../sync/pairs.js";
import { clearManifestCache } from "../core/manifest.js";
test('readSyncPairLines excludes restoreOnly on backup direction', () => {
    clearManifestCache();
    const lines = readSyncPairLines('macos', '1');
    assert.ok(lines.length > 0);
    // restoreOnly items like mirror-cli.zsh should not appear for direction 1
    assert.equal(lines.some((line) => line.includes('mirror-cli.zsh')), false);
});
test('readSyncPairLines includes restoreOnly on restore direction', () => {
    clearManifestCache();
    const lines = readSyncPairLines('macos', '2');
    assert.equal(lines.some((line) => line.includes('mirror-cli.zsh')), true);
});
