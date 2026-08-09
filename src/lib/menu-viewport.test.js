import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { menuChoicePageSize, menuWindow, terminalColumns, terminalRows } from "./menu-viewport.js";

describe('menu-viewport', () => {
    it('keeps cursor inside the window', () => {
        assert.deepEqual(menuWindow(0, 10, 0, 3), { offset: 0, end: 3 });
        assert.deepEqual(menuWindow(2, 10, 0, 3), { offset: 0, end: 3 });
        assert.deepEqual(menuWindow(3, 10, 0, 3), { offset: 1, end: 4 });
        assert.deepEqual(menuWindow(9, 10, 0, 3), { offset: 7, end: 10 });
        assert.deepEqual(menuWindow(1, 10, 5, 3), { offset: 1, end: 4 });
    });

    it('handles short lists and empty', () => {
        assert.deepEqual(menuWindow(0, 2, 0, 5), { offset: 0, end: 2 });
        assert.deepEqual(menuWindow(0, 0, 0, 5), { offset: 0, end: 0 });
    });

    it('derives page size from terminal rows', () => {
        assert.equal(menuChoicePageSize({ rows: 20 }, 5), 15);
        assert.equal(menuChoicePageSize({ rows: 3 }, 5), 1);
        assert.equal(terminalRows({}), 24);
        assert.equal(terminalColumns({}), 80);
        assert.equal(terminalColumns({ columns: 100 }), 100);
    });
});
