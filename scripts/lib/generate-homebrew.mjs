#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  renderBrewLite,
  renderHomebrewMirrorCatalog,
  writeBrewLiteBackup,
  writeHomebrewMirrorCatalog,
} from '../macos/homebrew-generated.mjs'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const manifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'scripts/macos/_manifest.json'), 'utf8'))
const checkOnly = process.argv.includes('--check')

const expectedCatalog = renderHomebrewMirrorCatalog(manifest)
const expectedLite = renderBrewLite(
  fs.readFileSync(path.join(projectRoot, manifest.brewfile), 'utf8'),
  manifest,
)

if (expectedLite.missing.length > 0) {
  throw new Error(`Homebrew lite items missing from Brewfile: ${expectedLite.missing.join(', ')}`)
}

if (checkOnly) {
  const currentCatalog = fs.readFileSync(path.join(projectRoot, manifest.brewMirrorCatalog), 'utf8')
  const currentLite = fs.readFileSync(path.join(projectRoot, manifest.brewfileLite), 'utf8')
  if (currentCatalog !== expectedCatalog || currentLite !== expectedLite.content) {
    console.error('Generated Homebrew files are stale; run: npm run generate:homebrew')
    process.exit(1)
  }
  console.log('Generated Homebrew files are current')
}
else {
  const catalog = writeHomebrewMirrorCatalog(projectRoot, manifest)
  const lite = writeBrewLiteBackup(projectRoot, manifest)
  console.log(`Generated Homebrew catalog (${catalog.written} mirrors) and lite Brewfile (${lite.written} items)`)
}
