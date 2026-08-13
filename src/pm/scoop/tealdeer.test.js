import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
    applyTldrMirror,
    buildTldrArchiveSource,
    renderTldrConfig,
    resolveTldrConfigPath,
    TLDR_ARCHIVE_URL,
    TLDR_DOWNLOAD_LANGUAGES,
} from "../../../runtime/scoop/mirror/tealdeer.js";

test('buildTldrArchiveSource joins prefix and official URL', () => {
    assert.equal(buildTldrArchiveSource('https://gh-proxy.com/'), `https://gh-proxy.com/${TLDR_ARCHIVE_URL}`);
    assert.equal(buildTldrArchiveSource('https://gh-proxy.com'), `https://gh-proxy.com/${TLDR_ARCHIVE_URL}`);
    assert.equal(buildTldrArchiveSource(''), TLDR_ARCHIVE_URL);
    assert.equal(buildTldrArchiveSource(undefined), TLDR_ARCHIVE_URL);
});

test('renderTldrConfig sets archive_source in existing [updates]', () => {
    const input = [
        '[directories]',
        'cache_dir = "c"',
        '',
        '[updates]',
        'auto_update = true',
        '',
        '[display]',
        'compact = false',
    ].join('\n');
    const out = renderTldrConfig(input, 'https://m.example.com/tldr/');
    assert.match(out, /\[updates\]/);
    assert.match(out, /archive_source = "https:\/\/m\.example\.com\/tldr\/"/);
    assert.match(out, /auto_update = false/);
    assert.match(out, /download_languages = \["en", "zh"\]/);
    assert.match(out, /\[directories\]/);
    assert.match(out, /cache_dir = "c"/);
    assert.match(out, /\[display\]/);
    assert.match(out, /compact = false/);
});

test('renderTldrConfig creates [updates] when absent', () => {
    const input = '[display]\ncompact = true\n';
    const out = renderTldrConfig(input, 'https://m.example.com/tldr/');
    assert.match(out, /\[updates\]/);
    assert.match(out, /archive_source = "https:\/\/m\.example\.com\/tldr\/"/);
    assert.match(out, /auto_update = false/);
    assert.match(out, /download_languages = \["en", "zh"\]/);
    assert.match(out, /\[display\]/);
    assert.match(out, /compact = true/);
});

test('renderTldrConfig replaces existing archive_source', () => {
    const input = [
        '[updates]',
        'archive_source = "https://old.example.com/"',
        'auto_update = true',
    ].join('\n');
    const out = renderTldrConfig(input, 'https://new.example.com/');
    assert.match(out, /archive_source = "https:\/\/new\.example\.com\/"/);
    assert.ok(!/old\.example\.com/.test(out));
    assert.match(out, /auto_update = false/);
    assert.match(out, /download_languages = \["en", "zh"\]/);
});

test('renderTldrConfig keeps trailing newline and skips auto_update when already present', () => {
    const input = '[updates]\nauto_update = true\n';
    const out = renderTldrConfig(input, 'https://m.example.com/');
    assert.ok(out.endsWith('\n'));
    assert.equal((out.match(/auto_update = false/g) || []).length, 1);
    assert.ok(!/auto_update = true/.test(out));
    assert.match(out, /archive_source = "https:\/\/m\.example\.com\/"/);
    assert.match(out, /download_languages = \["en", "zh"\]/);
});

test('renderTldrConfig replaces existing download_languages', () => {
    const input = [
        '[updates]',
        'download_languages = ["fr", "de"]',
    ].join('\n');
    const out = renderTldrConfig(input, 'https://m.example.com/');
    assert.equal((out.match(/download_languages = /g) || []).length, 1);
    assert.match(out, /download_languages = \["en", "zh"\]/);
    assert.ok(!/fr/.test(out));
    assert.deepEqual(TLDR_DOWNLOAD_LANGUAGES, ['en', 'zh']);
});

test('renderTldrConfig inserts missing keys inside existing [updates] section', () => {
    const input = [
        '[directories]',
        'cache_dir = "c"',
        '',
        '[updates]',
        'auto_update = true',
    ].join('\n');
    const out = renderTldrConfig(input, 'https://m.example.com/tldr/');
    const updatesHeader = out.indexOf('[updates]');
    const sourceIndex = out.indexOf('archive_source = "https://m.example.com/tldr/"');
    const langsIndex = out.indexOf('download_languages = ["en", "zh"]');
    assert.ok(updatesHeader >= 0, '[updates] header present');
    assert.ok(sourceIndex > updatesHeader, 'archive_source inserted after [updates] header');
    assert.ok(langsIndex > updatesHeader, 'download_languages inserted after [updates] header');
    assert.ok(langsIndex > sourceIndex, 'download_languages after archive_source');
});

test('resolveTldrConfigPath prefers SCOOP persist then TEALDEER_CONFIG_DIR then XDG', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-tldr-'));
    try {
        const scoop = path.join(root, 'scoop');
        const persist = path.join(scoop, 'persist', 'tealdeer', 'config.toml');
        fs.mkdirSync(path.dirname(persist), { recursive: true });
        fs.writeFileSync(persist, '[updates]\n');
        const env = { SCOOP: scoop, USERPROFILE: root, XDG_CONFIG_HOME: '' };
        assert.equal(resolveTldrConfigPath(env), persist);

        const explicitDir = path.join(root, 'explicit');
        fs.mkdirSync(explicitDir, { recursive: true });
        const explicit = path.join(explicitDir, 'config.toml');
        fs.writeFileSync(explicit, '[updates]\n');
        assert.equal(resolveTldrConfigPath({ SCOOP: '', TEALDEER_CONFIG_DIR: explicitDir, USERPROFILE: root, XDG_CONFIG_HOME: '' }), explicit);

        const xdg = path.join(root, '.config', 'tealdeer', 'config.toml');
        fs.mkdirSync(path.dirname(xdg), { recursive: true });
        fs.writeFileSync(xdg, '[updates]\n');
        assert.equal(resolveTldrConfigPath({ SCOOP: '', TEALDEER_CONFIG_DIR: '', USERPROFILE: root, XDG_CONFIG_HOME: '' }), xdg);

        assert.equal(resolveTldrConfigPath({ SCOOP: '', TEALDEER_CONFIG_DIR: '', USERPROFILE: root, XDG_CONFIG_HOME: '' }), xdg);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});

test('applyTldrMirror writes config and reports skipped when missing', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vpr-tldr-apply-'));
    try {
        const scoop = path.join(root, 'scoop');
        const persist = path.join(scoop, 'persist', 'tealdeer', 'config.toml');
        fs.mkdirSync(path.dirname(persist), { recursive: true });
        fs.writeFileSync(persist, '[directories]\ncache_dir = "c"\n');
        const env = { SCOOP: scoop, USERPROFILE: root, XDG_CONFIG_HOME: '' };

        const result = applyTldrMirror('https://gh-proxy.com/', env);
        assert.equal(result.applied, true);
        assert.equal(result.configPath, persist);
        assert.equal(result.archiveSource, `https://gh-proxy.com/${TLDR_ARCHIVE_URL}`);
        const content = fs.readFileSync(persist, 'utf8');
        assert.match(content, /\[updates\]/);
        assert.match(content, /archive_source = "https:\/\/gh-proxy\.com\//);
        assert.match(content, /download_languages = \["en", "zh"\]/);
        assert.match(content, /cache_dir = "c"/);

        const skipped = applyTldrMirror('https://gh-proxy.com/', { SCOOP: path.join(root, 'none'), USERPROFILE: root, XDG_CONFIG_HOME: '' });
        assert.equal(skipped.applied, false);
        assert.equal(skipped.configPath, null);
        assert.match(skipped.skipped, /not found/);
    }
    finally {
        fs.rmSync(root, { recursive: true, force: true });
    }
});
