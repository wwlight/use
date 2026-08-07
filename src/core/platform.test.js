import assert from 'node:assert/strict';
import test from 'node:test';
import { stripArgSeparator } from "./platform.js";
test('stripArgSeparator drops bare -- anywhere', () => {
    assert.deepEqual(stripArgSeparator(['init', '--', 'lite']), ['init', 'lite']);
    assert.deepEqual(stripArgSeparator(['--', 'init', 'lite']), ['init', 'lite']);
    assert.deepEqual(stripArgSeparator(['--', 'init', '--', 'lite', '--']), ['init', 'lite']);
    assert.deepEqual(stripArgSeparator(['init', 'lite']), ['init', 'lite']);
});
