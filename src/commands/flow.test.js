import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const here = dirname(fileURLToPath(import.meta.url));

test('zsh-plugin defaults to update; init opts out', () => {
    const zshPlugin = readFileSync(resolve(here, 'zsh-plugin.js'), 'utf8');
    const init = readFileSync(resolve(here, 'init.js'), 'utf8');

    assert.match(zshPlugin, /options\.update \?\? true/);
    assert.match(zshPlugin, /resolveZshPluginUpdate/);
    assert.match(zshPlugin, /--no-update/);
    assert.match(init, /runZshPluginCommand\(\[\],\s*\{\s*update:\s*false\s*\}\)/);
});

test('sync CLI accepts named directions and keeps numeric aliases', () => {
    const sync = readFileSync(resolve(here, 'sync.js'), 'utf8');
    const direction = readFileSync(resolve(here, '../sync/direction.js'), 'utf8');

    assert.match(sync, /normalizeSyncDirection/);
    assert.match(direction, /\['backup',\s*SYNC_DIRECTION_BACKUP\]/);
    assert.match(direction, /\['restore',\s*SYNC_DIRECTION_RESTORE\]/);
    assert.match(direction, /\['1',\s*SYNC_DIRECTION_BACKUP\]/);
    assert.match(direction, /\['2',\s*SYNC_DIRECTION_RESTORE\]/);
});
