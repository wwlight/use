import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { formatSyncChoiceLine } from "./select.js";
import { isSyncDirection, SYNC_DIRECTION_CHOICES, SYNC_DIRECTION_HINT } from "./direction.js";
const here = dirname(fileURLToPath(import.meta.url));
test('sync direction helpers', () => {
    assert.equal(isSyncDirection('1'), true);
    assert.equal(isSyncDirection('2'), true);
    assert.equal(isSyncDirection('3'), false);
    assert.equal(SYNC_DIRECTION_CHOICES.length, 2);
    assert.ok(SYNC_DIRECTION_HINT.includes('back up config'));
});
test('sync choice line formatting', () => {
    assert.equal(formatSyncChoiceLine('a.txt', { selected: true, active: false }), '  [✓] a.txt');
    assert.equal(formatSyncChoiceLine('b.txt', { selected: false, active: true }), '◇ [ ] b.txt');
    assert.equal(formatSyncChoiceLine('c.txt', { selected: true, active: true }), '◆ [✓] c.txt');
});
test('sync sources keep cancel + console behavior', () => {
    const syncSource = readFileSync(resolve(here, 'select.js'), 'utf8');
    const directionSource = readFileSync(resolve(here, 'direction.js'), 'utf8');
    assert.match(syncSource, /allowWindowsConsole:\s*true/);
    assert.match(syncSource, /console\.error\('Canceled'\)/);
    assert.match(syncSource, /key\.name === 'escape'/);
    assert.match(directionSource, /MENU_SELECT_OUT/);
    assert.match(directionSource, /console\.error\('Canceled'\)/);
});
