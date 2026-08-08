import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { projectRoot } from "../core/paths.js";
import { checkGithubAccelGenerated } from "./github-accel.js";

describe('github-accel', () => {
    it('keeps on-disk github-accel generated files current', () => {
        assert.deepEqual(checkGithubAccelGenerated(projectRoot()), { ok: true });
    });
});
