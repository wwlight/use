import assert from 'node:assert/strict';
import test from 'node:test';
import { consumeShiftSpaceSequence, formatSyncChoiceLine, invertChoices, isInvertKey, isToggleKey } from "./select.js";
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
    assert.equal(formatSyncChoiceLine('a.txt', { selected: true, active: false }), '  [✓] a.txt');
    assert.equal(formatSyncChoiceLine('b.txt', { selected: false, active: true }), '◇ [ ] b.txt');
    assert.equal(formatSyncChoiceLine('c.txt', { selected: true, active: true }), '◆ [✓] c.txt');
});

test('Space toggles one row; i / Shift+Space invert all', () => {
    assert.equal(isToggleKey(' ', { name: 'space', shift: false }), true);
    assert.equal(isToggleKey(' ', { name: 'space', shift: true }), false);
    assert.equal(isInvertKey(' ', { name: 'space', shift: true }), true);
    assert.equal(isInvertKey(' ', { name: 'space', meta: true }), true);
    assert.equal(isInvertKey('i', { name: 'i' }), true);
    assert.equal(isInvertKey(' ', { name: 'space', shift: false }), false);
    assert.equal(isInvertKey('x', { name: 'x', shift: true }), false);

    const choices = [
        { selected: true },
        { selected: false },
        { selected: true },
    ];
    invertChoices(choices);
    assert.deepEqual(choices.map((c) => c.selected), [false, true, false]);

    const hit = consumeShiftSpaceSequence('ab\x1b[27;2;32~cd');
    assert.equal(hit.matched, true);
    assert.equal(hit.buffer, 'abcd');
    assert.equal(consumeShiftSpaceSequence('plain').matched, false);
});
