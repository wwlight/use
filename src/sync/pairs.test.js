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
test('readSyncPairLines skips pmHelper pairs when SYNC_SKIP_PM_HELPERS=1', () => {
    clearManifestCache();
    const previous = process.env.SYNC_SKIP_PM_HELPERS;
    process.env.SYNC_SKIP_PM_HELPERS = '1';
    try {
        const mac = readSyncPairLines('macos', '2');
        assert.equal(mac.some((line) => line.includes('mirror-cli.zsh')), false);
        assert.ok(mac.some((line) => line.includes('.zshrc')));
        const win = readSyncPairLines('windows', '2');
        assert.equal(win.some((line) => line.includes('scoop-mirror')), false);
        assert.ok(win.some((line) => line.includes('.zshrc')));
    }
    finally {
        if (previous === undefined)
            delete process.env.SYNC_SKIP_PM_HELPERS;
        else
            process.env.SYNC_SKIP_PM_HELPERS = previous;
    }
});
