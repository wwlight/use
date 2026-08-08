import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { formatAlignedChoices, formatChoiceLine, parseChoice } from "./menu-select.js";
import { alignMenuCheck, MENU_CHECK, stringWidth } from "./string-width.js";
describe('menu-select', () => {
    it('parses choice lines', () => {
        assert.deepEqual(parseChoice('lite) 尝鲜版'), { value: 'lite', label: '尝鲜版' });
        assert.deepEqual(parseChoice('1) 备份配置 → 仓库'), { value: '1', label: '备份配置 → 仓库' });
        assert.deepEqual(parseChoice('ustc) * ustc ---------- https://example/'), {
            value: 'ustc',
            label: '* ustc ---------- https://example/',
        });
        // Inactive mark is a space — must not be trimStart'd away (keeps * column aligned).
        assert.deepEqual(parseChoice('tuna)   tuna ---------- https://example/'), {
            value: 'tuna',
            label: '  tuna ---------- https://example/',
        });
        assert.throws(() => parseChoice('nocolon'), /Expected option format/);
    });
    it('aligns choice columns', () => {
        const aligned = formatAlignedChoices([
            { value: 'npm', name: 'npm', detail: 'https://registry.npmjs.org/' },
            { value: 'jd', name: 'jd', detail: 'http://registry.m.jd.com/' },
            { value: 'official', name: 'official', detail: 'https://github.com/' },
        ], { activeValue: 'jd' });
        assert.equal(aligned[0].value, 'npm');
        assert.equal(aligned[1].value, 'jd');
        // Shorter names absorb the gap as extra dashes (not spaces).
        assert.equal(aligned[0].label, '  npm --------------- https://registry.npmjs.org/');
        assert.equal(aligned[1].label, '* jd ---------------- http://registry.m.jd.com/');
        assert.equal(aligned[2].label, '  official ---------- https://github.com/');
        assert.equal(aligned[0].label[0], ' ');
        assert.equal(aligned[1].label[0], '*');
        assert.equal(aligned[2].label[0], ' ');
        assert.equal(aligned[0].label.indexOf('npm'), 2);
        assert.equal(aligned[1].label.indexOf('jd'), 2);
        assert.equal(aligned[2].label.indexOf('official'), 2);
        assert.equal(aligned[0].label.indexOf('http'), aligned[1].label.indexOf('http'));
        assert.equal(aligned[1].label.indexOf('http'), aligned[2].label.indexOf('http'));
    });
    it('menu check column is stable for active and idle', () => {
        assert.equal(MENU_CHECK, '➤');
        assert.equal(alignMenuCheck(true), '➤');
        assert.equal(alignMenuCheck(false), ' ');
        assert.equal(formatChoiceLine('label', true), '➤ label');
        assert.equal(formatChoiceLine('label', false), '  label');
        const narrow = { ambiguousWide: false };
        assert.equal(stringWidth(alignMenuCheck(true), narrow), stringWidth(alignMenuCheck(false), narrow));
    });
});
