#!/usr/bin/env node
/**
 * Homebrew artifacts: mirrors.tsv (mirror catalog) + Brewfile.lite (lite profile).
 * CLI: node src/generate/brew-artifacts.js [--check]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { projectRoot } from "../core/paths.js";
const CATALOG_HEADER = '# use-homebrew-mirrors-v1';
const BREW_DIRECTIVE = /^\s*(tap|brew|cask|mas|vscode|whalebrew)\s+"([^"]+)"/;
function atomicWrite(filePath, content) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    const temp = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(temp, content, { encoding: 'utf8', mode: 0o644 });
    fs.renameSync(temp, filePath);
}
function cleanField(value, field) {
    const text = String(value ?? '').trim();
    if (/[\t\r\n]/.test(text))
        throw new Error(`${field} contains a tab or newline`);
    return text;
}
function validateUrl(value, field) {
    const text = cleanField(value, field);
    if (!text)
        return '';
    let url;
    try {
        url = new URL(text);
    }
    catch {
        throw new Error(`${field} is not a valid URL: ${text}`);
    }
    if (url.protocol !== 'https:')
        throw new Error(`${field} must use https: ${text}`);
    return text;
}
export function listBrewMirrors(manifest) {
    const entries = Object.entries(manifest.brewMirrors || {});
    if (entries.length === 0)
        throw new Error('macos manifest brewMirrors must not be empty');
    const seen = new Set();
    return entries.map(([rawId, raw]) => {
        const id = cleanField(rawId, 'mirror id');
        const label = cleanField(raw?.label, `${id}.label`);
        if (!/^[a-z0-9][a-z0-9-]*$/.test(id))
            throw new Error(`Invalid Homebrew mirror id: ${id}`);
        if (!label)
            throw new Error(`Homebrew mirror ${id} is missing a label`);
        if (seen.has(id))
            throw new Error(`Duplicate Homebrew mirror id: ${id}`);
        seen.add(id);
        const mirror = {
            id,
            label,
            apiDomain: validateUrl(raw?.apiDomain, `${id}.apiDomain`),
            bottleDomain: validateUrl(raw?.bottleDomain, `${id}.bottleDomain`),
            brewGitRemote: validateUrl(raw?.brewGitRemote, `${id}.brewGitRemote`),
        };
        if (id !== 'official' && (!mirror.apiDomain || !mirror.bottleDomain || !mirror.brewGitRemote)) {
            throw new Error(`Homebrew mirror ${id} must define API, bottle, and Brew Git URLs`);
        }
        return mirror;
    });
}
export function renderBrewMirrorCatalog(manifest) {
    const rows = listBrewMirrors(manifest).map((mirror) => [
        mirror.id,
        mirror.label,
        mirror.apiDomain || '-',
        mirror.bottleDomain || '-',
        mirror.brewGitRemote || '-',
    ].join('\t'));
    return `${CATALOG_HEADER}\n${rows.join('\n')}\n`;
}
function parseBrewfile(content) {
    const records = [];
    let pending = [];
    for (const line of content.split(/\r?\n/)) {
        const match = line.match(BREW_DIRECTIVE);
        if (match) {
            records.push({
                type: match[1],
                name: match[2],
                lines: [...pending, line],
            });
            pending = [];
        }
        else if (!line.trim() || line.trimStart().startsWith('#')) {
            pending.push(line);
        }
        else {
            pending = [];
        }
    }
    return records;
}
function liteKeys(manifest) {
    if (!Array.isArray(manifest.brewLiteItems) || manifest.brewLiteItems.length === 0) {
        throw new Error('macos manifest brewLiteItems must not be empty');
    }
    const keys = [];
    const seen = new Set();
    for (const item of manifest.brewLiteItems) {
        const type = cleanField(item?.type, 'brewLiteItems.type');
        const name = cleanField(item?.name, 'brewLiteItems.name');
        if (!type || !name)
            throw new Error('brewLiteItems entries require type and name');
        const key = `${type}:${name}`;
        if (seen.has(key))
            throw new Error(`Duplicate brewLiteItems entry: ${key}`);
        seen.add(key);
        keys.push(key);
    }
    return keys;
}
function requiredTap(name) {
    const parts = name.split('/');
    return parts.length >= 3 ? `${parts[0]}/${parts[1]}` : '';
}
export function renderBrewLite(fullContent, manifest) {
    const records = parseBrewfile(fullContent);
    const byKey = new Map(records.map((record) => [`${record.type}:${record.name}`, record]));
    const selectedKeys = liteKeys(manifest);
    const missing = selectedKeys.filter((key) => !byKey.has(key));
    const selected = new Set(selectedKeys);
    for (const key of selectedKeys) {
        const record = byKey.get(key);
        if (!record)
            continue;
        const tap = requiredTap(record.name);
        if (tap && byKey.has(`tap:${tap}`))
            selected.add(`tap:${tap}`);
    }
    const lines = ['# Generated from Brewfile using manifests/macos.json brewLiteItems.'];
    for (const record of records) {
        if (!selected.has(`${record.type}:${record.name}`))
            continue;
        while (lines.length > 1 && lines.at(-1) === '' && record.lines[0] === '')
            lines.pop();
        lines.push(...record.lines);
    }
    while (lines.at(-1) === '')
        lines.pop();
    return { content: `${lines.join('\n')}\n`, missing, written: selectedKeys.length - missing.length };
}
export function writeBrewMirrorCatalog(projectRoot, manifest) {
    const relative = manifest.brewMirrorCatalog;
    if (!relative)
        throw new Error('macos manifest is missing brewMirrorCatalog');
    const content = renderBrewMirrorCatalog(manifest);
    atomicWrite(path.join(projectRoot, relative), content);
    return { content, written: listBrewMirrors(manifest).length };
}
export function writeBrewLiteBackup(projectRoot, manifest) {
    if (!manifest.brewfile || !manifest.brewfileLite) {
        throw new Error('macos manifest is missing brewfile / brewfileLite');
    }
    const fullPath = path.join(projectRoot, manifest.brewfile);
    const litePath = path.join(projectRoot, manifest.brewfileLite);
    const result = renderBrewLite(fs.readFileSync(fullPath, 'utf8'), manifest);
    atomicWrite(litePath, result.content);
    return result;
}

function loadMacosManifest(root) {
    return JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'));
}

/** @returns {{ ok: true } | { ok: false, reason: string }} */
export function checkBrewGenerated(root = projectRoot()) {
    const manifest = loadMacosManifest(root);
    const expectedCatalog = renderBrewMirrorCatalog(manifest);
    const expectedLite = renderBrewLite(fs.readFileSync(path.join(root, manifest.brewfile), 'utf8'), manifest);
    if (expectedLite.missing.length > 0) {
        throw new Error(`Brew lite items missing from Brewfile: ${expectedLite.missing.join(', ')}`);
    }
    const currentCatalog = fs.readFileSync(path.join(root, manifest.brewMirrorCatalog), 'utf8');
    const currentLite = fs.readFileSync(path.join(root, manifest.brewfileLite), 'utf8');
    if (currentCatalog !== expectedCatalog || currentLite !== expectedLite.content) {
        return { ok: false, reason: 'Generated brew files are stale; run: npm run generate:brew' };
    }
    return { ok: true };
}

export function generateBrewFiles(root = projectRoot()) {
    const manifest = loadMacosManifest(root);
    const expectedLite = renderBrewLite(fs.readFileSync(path.join(root, manifest.brewfile), 'utf8'), manifest);
    if (expectedLite.missing.length > 0) {
        throw new Error(`Brew lite items missing from Brewfile: ${expectedLite.missing.join(', ')}`);
    }
    const catalog = writeBrewMirrorCatalog(root, manifest);
    const lite = writeBrewLiteBackup(root, manifest);
    return { catalog, lite };
}

function main() {
    if (process.argv.includes('--check')) {
        const result = checkBrewGenerated();
        if (!result.ok) {
            console.error(result.reason);
            process.exit(1);
        }
        console.log('Generated brew files are current');
        return;
    }
    const { catalog, lite } = generateBrewFiles();
    console.log(`Generated brew catalog (${catalog.written} mirrors) and lite Brewfile (${lite.written} items)`);
}

const isDirectRun = Boolean(process.argv[1])
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun)
    main();
