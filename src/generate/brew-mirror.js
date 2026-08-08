#!/usr/bin/env node
/**
 * Homebrew mirror catalog: mirrors.tsv from manifest brewMirrors.
 * CLI: node src/generate/brew-mirror.js [--check]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { projectRoot } from "../core/paths.js";
const CATALOG_HEADER = '# use-homebrew-mirrors-v1';
function normalizeEol(text) {
    return String(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}
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
export function writeBrewMirrorCatalog(projectRoot, manifest) {
    const relative = manifest.brewMirrorCatalog;
    if (!relative)
        throw new Error('macos manifest is missing brewMirrorCatalog');
    const content = renderBrewMirrorCatalog(manifest);
    atomicWrite(path.join(projectRoot, relative), content);
    return { content, written: listBrewMirrors(manifest).length };
}
function loadMacosManifest(root) {
    return JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'));
}
/** @returns {{ ok: true } | { ok: false, reason: string }} */
export function checkBrewMirrorGenerated(root = projectRoot()) {
    const manifest = loadMacosManifest(root);
    const expectedCatalog = renderBrewMirrorCatalog(manifest);
    const currentCatalog = fs.readFileSync(path.join(root, manifest.brewMirrorCatalog), 'utf8');
    if (normalizeEol(currentCatalog) !== normalizeEol(expectedCatalog)) {
        return { ok: false, reason: 'Generated brew mirror catalog is stale; run: vpr generate brew-mirror' };
    }
    return { ok: true };
}
export function generateBrewMirrorFiles(root = projectRoot()) {
    const catalog = writeBrewMirrorCatalog(root, loadMacosManifest(root));
    return { catalog };
}
function main() {
    if (process.argv.includes('--check')) {
        const result = checkBrewMirrorGenerated();
        if (!result.ok) {
            console.error(result.reason);
            process.exit(1);
        }
        console.log('Generated brew catalog is current');
        return;
    }
    const { catalog } = generateBrewMirrorFiles();
    console.log(`Generated brew catalog (${catalog.written} mirrors)`);
}
const isDirectRun = Boolean(process.argv[1])
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun)
    main();
