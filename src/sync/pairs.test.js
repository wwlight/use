import assert from 'node:assert/strict';
import test from 'node:test';
import { formatLocalDisplay, readSyncItems, readSyncPairLines, syncGroupKey } from "../sync/pairs.js";
import { clearManifestCache } from "../core/manifest.js";

function assertContiguousPrefix(displays, prefix) {
    const indexes = displays
        .map((p, i) => (p === prefix || p.startsWith(`${prefix}/`) ? i : -1))
        .filter((i) => i >= 0);
    if (indexes.length === 0)
        return;
    assert.equal(
        indexes[indexes.length - 1] - indexes[0] + 1,
        indexes.length,
        `${prefix} items should be contiguous: ${displays.join(' | ')}`,
    );
}

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
        assert.equal(win.some((line) => line.includes('mirror/cli.js')), false);
        assert.ok(win.some((line) => line.includes('.zshrc')));
    }
    finally {
        if (previous === undefined)
            delete process.env.SYNC_SKIP_PM_HELPERS;
        else
            process.env.SYNC_SKIP_PM_HELPERS = previous;
    }
});

test('syncGroupKey buckets home path prefixes', () => {
    assert.equal(syncGroupKey('~/.zshrc'), '0:~');
    assert.equal(syncGroupKey('~/.bashrc'), '0:~');
    assert.equal(syncGroupKey('~/.zsh/functions/utils.zsh'), '1:~/.zsh');
    assert.equal(syncGroupKey('~/.config/scoop/scoop.ps1'), '2:~/.config');
    assert.equal(syncGroupKey('~/Documents/PowerShell/profile.ps1'), '3:~/Documents');
    assert.ok(syncGroupKey('D:/SoftwareApps/Scoop/persist/x').startsWith('9:other:'));
});

test('readSyncItems groups ~/.zsh and ~/.config contiguously on windows', () => {
    clearManifestCache();
    const displays = readSyncItems('windows', '2').map((item) => formatLocalDisplay(item.local));
    assertContiguousPrefix(displays, '~/.zsh');
    assertContiguousPrefix(displays, '~/.config');
    const zshIdx = displays.findIndex((p) => p.startsWith('~/.zsh/') || p === '~/.zsh');
    const configIdx = displays.findIndex((p) => p.startsWith('~/.config/') || p === '~/.config');
    const homeDotIdx = displays.findIndex((p) => p === '~/.zshrc' || p === '~/.bashrc');
    assert.ok(homeDotIdx >= 0);
    assert.ok(zshIdx >= 0);
    assert.ok(configIdx >= 0);
    assert.ok(homeDotIdx < zshIdx);
    assert.ok(zshIdx < configIdx);
});

test('readSyncItems groups ~/.zsh and ~/.config contiguously on macos', () => {
    clearManifestCache();
    const displays = readSyncItems('macos', '2').map((item) => formatLocalDisplay(item.local));
    assertContiguousPrefix(displays, '~/.zsh');
    assertContiguousPrefix(displays, '~/.config');
});
