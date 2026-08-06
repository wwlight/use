#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { projectRoot } from "../core/paths.js";
import { renderBrewLite, renderBrewMirrorCatalog, writeBrewLiteBackup, writeBrewMirrorCatalog, } from "./brew.js";
const root = projectRoot();
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'));
const checkOnly = process.argv.includes('--check');
const expectedCatalog = renderBrewMirrorCatalog(manifest);
const expectedLite = renderBrewLite(fs.readFileSync(path.join(root, manifest.brewfile), 'utf8'), manifest);
if (expectedLite.missing.length > 0) {
    throw new Error(`Brew lite items missing from Brewfile: ${expectedLite.missing.join(', ')}`);
}
if (checkOnly) {
    const currentCatalog = fs.readFileSync(path.join(root, manifest.brewMirrorCatalog), 'utf8');
    const currentLite = fs.readFileSync(path.join(root, manifest.brewfileLite), 'utf8');
    if (currentCatalog !== expectedCatalog || currentLite !== expectedLite.content) {
        console.error('Generated brew files are stale; run: npm run generate:brew');
        process.exit(1);
    }
    console.log('Generated brew files are current');
}
else {
    const catalog = writeBrewMirrorCatalog(root, manifest);
    const lite = writeBrewLiteBackup(root, manifest);
    console.log(`Generated brew catalog (${catalog.written} mirrors) and lite Brewfile (${lite.written} items)`);
}
