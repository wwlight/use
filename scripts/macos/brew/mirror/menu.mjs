#!/usr/bin/env node
/**
 * Interactive Homebrew mirror picker (deployed to ~/.config/homebrew/lib/menu.mjs).
 *
 * Usage: node menu.mjs <catalog.tsv> [activeId]
 * Prints the selected mirror id to stdout. Exit 130 on cancel.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))

async function loadMenuModule() {
  for (const candidate of [
    path.join(here, 'menu-select.mjs'),
    path.resolve(here, '../../../lib/menu-select.mjs'),
  ]) {
    if (fs.existsSync(candidate)) {
      return import(pathToFileURL(candidate).href)
    }
  }
  throw new Error('menu-select.mjs not found (re-run vpr pm / sync)')
}

function loadCatalogRows(catalogPath) {
  if (!fs.existsSync(catalogPath)) {
    throw new Error(`brew mirror: catalog not found at ${catalogPath}`)
  }
  const raw = fs.readFileSync(catalogPath, 'utf8')
  const lines = raw.trim().split('\n')
  const header = lines[0] || ''
  if (header !== '# use-homebrew-mirrors-v1') {
    throw new Error(`brew mirror: unsupported catalog header in ${catalogPath}`)
  }
  const rows = []
  for (const line of lines.slice(1)) {
    if (!line || line.startsWith('#')) continue
    const [id, label, api, bottle, git] = line.split('\t')
    if (!id) continue
    if (!label || !api || !bottle || !git) {
      throw new Error(`brew mirror: invalid catalog row for ${id}`)
    }
    const detail = (api !== '-') ? api : ((git !== '-') ? git : label)
    rows.push({ value: id, name: id, detail })
  }
  if (rows.length === 0) {
    throw new Error('brew mirror: catalog is empty')
  }
  return rows
}

const catalogPath = process.argv[2]
const active = process.argv[3] || ''
if (!catalogPath) {
  console.error('Usage: node menu.mjs <catalog.tsv> [activeId]')
  process.exit(1)
}

try {
  const mod = await loadMenuModule()
  const rows = loadCatalogRows(catalogPath)
  const choices = mod.formatAlignedChoices(rows, { activeValue: active })
  const value = await mod.runMenuSelect({
    message: 'Choose a Homebrew mirror',
    choices,
    initialValue: active,
  })
  process.stdout.write(`${String(value).trim()}\n`)
}
catch (err) {
  if (err?.code === 'CANCELLED') process.exit(130)
  console.error(err?.message || String(err))
  process.exit(1)
}
