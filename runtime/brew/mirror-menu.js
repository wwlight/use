#!/usr/bin/env node
/**
 * Interactive Homebrew mirror picker (deployed to ~/.config/homebrew/lib/mirror-menu.js).
 *
 * Usage: node mirror-menu.js <catalog.tsv> [activeId]
 * Prints the selected mirror id to stdout. Exit 130 on cancel.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))

function findRepoRoot(startDir) {
  let dir = path.resolve(startDir)
  for (;;) {
    if (fs.existsSync(path.join(dir, 'manifests', 'common.json'))) return dir
    const parent = path.dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

async function loadMenuModule() {
  const candidates = [path.join(here, 'menu-select.js')]
  const root = findRepoRoot(here)
  if (root) candidates.push(path.join(root, 'src/lib/menu-select.js'))
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return import(pathToFileURL(candidate).href)
    }
  }
  throw new Error('menu-select.js not found (re-run vpr pm / sync)')
}

function loadCatalogRows(catalogPath) {
    if (!fs.existsSync(catalogPath)) {
        throw new Error(`brew mirror: catalog not found at ${catalogPath}`);
    }
    const raw = fs.readFileSync(catalogPath, 'utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines = raw.trim().split('\n');
    const header = (lines[0] || '').replace(/\r$/, '');
    if (header !== '# use-homebrew-mirrors-v1') {
        throw new Error(`brew mirror: unsupported catalog header in ${catalogPath}`);
    }
    const rows = [];
    for (const line of lines.slice(1)) {
        if (!line || line.startsWith('#'))
            continue;
        const [id, label, api, bottle, git] = line.split('\t').map((part) => String(part ?? '').replace(/\r$/, ''));
        if (!id)
            continue;
        if (!label || !api || !bottle || !git) {
            throw new Error(`brew mirror: invalid catalog row for ${id}`);
        }
        const detail = (label !== '-') ? label : ((api !== '-') ? api : git);
        rows.push({ value: id, name: id, detail });
    }
    if (rows.length === 0) {
        throw new Error('brew mirror: catalog is empty');
    }
    return rows;
}
const catalogPath = process.argv[2];
const active = process.argv[3] || '';
if (!catalogPath) {
    console.error('Usage: node mirror-menu.js <catalog.tsv> [activeId]');
    process.exit(1);
}
try {
    const mod = await loadMenuModule();
    const rows = loadCatalogRows(catalogPath);
    const choices = mod.formatAlignedChoices(rows, { activeValue: active });
    const value = await mod.runMenuSelect({
        message: 'Choose a Homebrew mirror',
        choices,
        initialValue: active,
    });
    const text = `${String(value).trim()}\n`;
    const outFile = process.env.MENU_SELECT_OUT;
    if (outFile) {
        fs.writeFileSync(outFile, text, 'utf8');
    }
    else {
        process.stdout.write(text);
    }
}
catch (err) {
    if (err?.code === 'CANCELLED') {
        console.error('\x1b[2mCanceled\x1b[0m');
        process.exit(130);
    }
    console.error(err?.message || String(err));
    process.exit(1);
}
