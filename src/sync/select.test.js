import assert from 'node:assert/strict';
import test from 'node:test';
import { formatSyncChoiceLine } from "./select.js";
import { isSyncDirection, normalizeSyncDirection, SYNC_DIRECTION_BACKUP, SYNC_DIRECTION_CHOICES, SYNC_DIRECTION_HINT, SYNC_DIRECTION_RESTORE, } from "./direction.js";
test('sync direction helpers', () => {
    assert.equal(isSyncDirection('1'), true);
    assert.equal(isSyncDirection('2'), true);
    assert.equal(isSyncDirection('backup'), true);
    assert.equal(isSyncDirection('restore'), true);
    assert.equal(isSyncDirection('BACKUP'), true);
    assert.equal(isSyncDirection('3'), false);
    assert.equal(normalizeSyncDirection('1'), SYNC_DIRECTION_BACKUP);
    assert.equal(normalizeSyncDirection('backup'), SYNC_DIRECTION_BACKUP);
    assert.equal(normalizeSyncDirection('2'), SYNC_DIRECTION_RESTORE);
    assert.equal(normalizeSyncDirection('restore'), SYNC_DIRECTION_RESTORE);
    assert.equal(normalizeSyncDirection('nope'), null);
    assert.equal(SYNC_DIRECTION_CHOICES.length, 2);
    assert.ok(SYNC_DIRECTION_HINT.includes('back up config'));
    assert.ok(SYNC_DIRECTION_HINT.includes('backup'));
    assert.ok(SYNC_DIRECTION_HINT.includes('restore'));
});
test('sync choice line formatting', () => {
    assert.equal(formatSyncChoiceLine('a.txt', { selected: true, active: false }), '  [✔] a.txt');
    assert.equal(formatSyncChoiceLine('b.txt', { selected: false, active: true }), '◇ [ ] b.txt');
    assert.equal(formatSyncChoiceLine('c.txt', { selected: true, active: true }), '◆ [✔] c.txt');
});
