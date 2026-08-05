import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const read = (path) => readFileSync(resolve(root, path), 'utf8')

const common = JSON.parse(read('scripts/common/_manifest.json'))
const mirrorIds = common.githubAccel.mirrors.map(({ id }) => id)
const mirrorPrefixes = common.githubAccel.mirrors.map(({ prefix }) => prefix)

assert.equal(new Set(mirrorIds).size, mirrorIds.length)
assert.equal(new Set(mirrorPrefixes).size, mirrorPrefixes.length)
assert.ok(mirrorIds.includes(common.githubAccel.default))

const installer = read('scripts/windows/scoop-accel.ps1')
assert.match(installer, /mirrors\s*=\s*\$mirrors/)
assert.match(installer, /scoopRepo\s*=\s*\[string\]\$Accel\.scoopRepo/)

const helper = read('scripts/windows/mirror-accel.ps1')
assert.match(helper, /\[switch\]\$ManageMirror/)
assert.match(helper, /Set-ScoopMirrorBucketRemotes/)
assert.match(helper, /scoop config scoop_repo \$repo/)
assert.match(helper, /Scoop source: cache/)
assert.match(helper, /return 'direct'/)
assert.match(helper, /GitHub mirror unavailable for this host/)
assert.match(helper, /configured GitHub mirrors cannot proxy/)

for (const profile of [
  'configs/windows/pwsh5_profile.ps1',
  'configs/windows/pwsh7_profile.ps1',
  'configs/windows/scoop_services.zsh',
]) {
  const content = read(profile)
  assert.match(content, /['"]mirror['"]/)
  assert.match(content, /-ManageMirror/)
  assert.match(content, /-MirrorChoice/)
}

const readme = read('README.md')
const mirrorSection = readme.match(/### scoop mirror\n([\s\S]*?)\n### scoop services/)
assert.ok(mirrorSection)
for (const command of ['scoop mirror', 'scoop mirror list', 'scoop mirror ghfast', 'scoop mirror ghproxy', 'scoop mirror official']) {
  assert.ok(mirrorSection[1].includes(command))
}

console.log('scoop-mirror.test.mjs: ok')
