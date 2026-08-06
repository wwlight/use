import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import {
  homebrewMirrors,
  renderBrewLite,
  renderHomebrewMirrorCatalog,
} from './generated.mjs'

const root = path.resolve(import.meta.dirname, '../../..')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'scripts/macos/_manifest.json'), 'utf8'))
const full = fs.readFileSync(path.join(root, manifest.brewfile), 'utf8')

const mirrors = homebrewMirrors(manifest)
assert.deepEqual(mirrors.map(({ id }) => id), ['ustc', 'tuna', 'official'])
assert.match(renderHomebrewMirrorCatalog(manifest), /^# use-homebrew-mirrors-v1\n/)
assert.match(renderHomebrewMirrorCatalog(manifest), /^official\t官方源\t-\t-\t-$/m)
assert.throws(
  () => renderHomebrewMirrorCatalog({
    brewMirrors: { bad: { label: 'Bad', apiDomain: 'http://insecure.test' } },
  }),
  /https/,
)

const lite = renderBrewLite(full, manifest)
assert.deepEqual(lite.missing, [])
assert.equal(lite.written, manifest.brewLiteItems.length)
for (const { type, name } of manifest.brewLiteItems) {
  assert.match(lite.content, new RegExp(`^${type} "${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`, 'm'))
}
assert.ok(!lite.content.includes('brew "mysql"'))
assert.ok(!lite.content.includes('cask "google-chrome"'))

const tapped = renderBrewLite(
  'tap "owner/tap", trusted: true\nbrew "owner/tap/tool"\nbrew "other"\n',
  { brewLiteItems: [{ type: 'brew', name: 'owner/tap/tool' }] },
)
assert.match(tapped.content, /tap "owner\/tap"/)
assert.match(tapped.content, /brew "owner\/tap\/tool"/)
assert.ok(!tapped.content.includes('brew "other"'))

console.log('macos/brew/generated.test.mjs: ok')
