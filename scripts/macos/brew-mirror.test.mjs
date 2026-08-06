import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '../..')
const helper = path.join(root, 'configs/macos/brew-mirror.zsh')
const source = fs.readFileSync(helper, 'utf8')
const installer = fs.readFileSync(path.join(root, 'scripts/macos/brew-install.sh'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'scripts/macos/_manifest.json'), 'utf8'))

for (const [id, config] of Object.entries(manifest.brewMirrors)) {
  if (id === 'official') continue
  assert.match(source, new RegExp(config.apiDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  assert.match(source, new RegExp(config.bottleDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  assert.match(source, new RegExp(config.brewGitRemote.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
}
assert.match(source, /fzf/)
assert.match(source, /中科大镜像/)
assert.match(source, /清华镜像/)
assert.match(source, /官方源/)
assert.match(installer, /deploy_brew_mirror/)
assert.match(installer, /configs\/macos\/brew-mirror\.zsh/)
assert.ok(!/\}\s*>\s*"\$file"/.test(installer))

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'use-brew-mirror-'))
const bin = path.join(temp, 'bin')
fs.mkdirSync(bin)
const fakeBrew = path.join(bin, 'brew')
fs.writeFileSync(fakeBrew, '#!/bin/sh\n[ "$1" = shellenv ] && printf "export PATH=/fake/homebrew/bin:$PATH\\n"\n')
fs.chmodSync(fakeBrew, 0o755)
fs.writeFileSync(path.join(temp, '.zprofile'), 'export KEEP_THIS_SETTING=yes\n')

const script = `
set -eu
source "$HELPER"
export HOMEBREW_API_DOMAIN=old-api
export HOMEBREW_BOTTLE_DOMAIN=old-bottle
export HOMEBREW_BREW_GIT_REMOTE=old-git

brew-mirror ustc >/dev/null
test "$USE_HOMEBREW_MIRROR" = ustc
test "$HOMEBREW_API_DOMAIN" = "https://mirrors.ustc.edu.cn/homebrew-bottles/api"

brew-mirror tuna >/dev/null
test "$USE_HOMEBREW_MIRROR" = tuna
test "$HOMEBREW_BREW_GIT_REMOTE" = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"

brew-mirror official >/dev/null
test "$USE_HOMEBREW_MIRROR" = official
test -z "\${HOMEBREW_API_DOMAIN+x}"
test -z "\${HOMEBREW_BOTTLE_DOMAIN+x}"
test -z "\${HOMEBREW_BREW_GIT_REMOTE+x}"
brew-mirror status | grep -q "Active Homebrew mirror: official"
`
const result = spawnSync('bash', ['-c', script], {
  encoding: 'utf8',
  env: {
    ...process.env,
    HELPER: helper,
    HOME: temp,
    PATH: `${bin}:${process.env.PATH}`,
    XDG_CONFIG_HOME: path.join(temp, '.config'),
  },
})
assert.equal(result.status, 0, result.stderr || result.stdout)

const profile = fs.readFileSync(path.join(temp, '.zprofile'), 'utf8')
assert.match(profile, /export KEEP_THIS_SETTING=yes/)
assert.equal((profile.match(/# >>> use-homebrew/g) || []).length, 1)
assert.equal((profile.match(/# <<< use-homebrew/g) || []).length, 1)
assert.match(profile, /mirror\.zsh/)
assert.match(profile, /brew shellenv/)

const persisted = fs.readFileSync(path.join(temp, '.config/homebrew/mirror.zsh'), 'utf8')
assert.match(persisted, /export USE_HOMEBREW_MIRROR=official/)
assert.match(persisted, /unset HOMEBREW_API_DOMAIN/)

fs.rmSync(temp, { recursive: true, force: true })
console.log('macos/brew-mirror.test.mjs: ok')
