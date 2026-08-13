import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { deployRuntimeFiles, staleRuntimeFiles } from "./runtime-deploy.js";

describe('runtime-deploy', () => {
    it('records state and reports no stale files after deploy', async () => {
        const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-deploy-'));
        try {
            const srcA = path.join(root, 'a.js');
            const srcB = path.join(root, 'b.ps1');
            const destA = path.join(root, 'out', 'lib', 'a.js');
            const destB = path.join(root, 'out', 'b.ps1');
            fs.writeFileSync(srcA, 'console.log(1)\n');
            fs.writeFileSync(srcB, 'Write-Host hi\n');
            const statePath = path.join(root, 'out', '.use-deploy-state.json');
            const plan = [
                { src: srcA, dest: destA },
                { src: srcB, dest: destB, encoding: 'utf8Bom' },
            ];

            await deployRuntimeFiles(plan, statePath);
            assert.equal(fs.existsSync(destA), true);
            assert.equal(fs.readFileSync(destB)[0], 0xEF, 'utf8Bom deployed');
            assert.deepEqual(staleRuntimeFiles(plan, statePath), []);
        }
        finally {
            fs.rmSync(root, { recursive: true, force: true });
        }
    });

    it('reports changed and missing files as stale', async () => {
        const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-deploy-stale-'));
        try {
            const srcA = path.join(root, 'a.js');
            const srcB = path.join(root, 'b.ps1');
            const destA = path.join(root, 'out', 'a.js');
            const destB = path.join(root, 'out', 'b.ps1');
            fs.writeFileSync(srcA, 'v1\n');
            fs.writeFileSync(srcB, 'v1\n');
            const statePath = path.join(root, 'out', '.use-deploy-state.json');
            const plan = [
                { src: srcA, dest: destA },
                { src: srcB, dest: destB },
            ];
            await deployRuntimeFiles(plan, statePath);

            fs.writeFileSync(srcA, 'v2\n');
            fs.rmSync(destB, { force: true });

            const stale = staleRuntimeFiles(plan, statePath);
            assert.deepEqual(stale.map((p) => path.basename(p)).sort(), ['a.js', 'b.ps1']);
        }
        finally {
            fs.rmSync(root, { recursive: true, force: true });
        }
    });
});