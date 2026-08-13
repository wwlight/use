import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const helper = path.join(root, 'runtime/brew/mirror-cli.zsh')
const catalog = path.join(root, 'configs/macos/brew/mirrors.tsv')
const source = fs.readFileSync(helper, 'utf8')
const brewPm = fs.readFileSync(path.join(root, 'src/pm/brew/index.js'), 'utf8')
const brewMirror = fs.readFileSync(path.join(root, 'src/pm/brew/mirror.js'), 'utf8')
const installSh = fs.readFileSync(path.join(root, 'install.sh'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'))

// Helper + JS wiring contracts.
assert.match(source, /mirrors\.tsv/)
assert.match(source, /use-homebrew-mirrors-v1/)
assert.match(source, /^brew\(\) \{/m)
assert.match(source, /_brew_mirror_cli/)
assert.match(source, /_brew_mirror_find_brew/)
assert.match(source, /mirror-menu\.js/)
assert.match(source, /MENU_SELECT_OUT/)
assert.ok(!/command brew "\$@"/.test(source))
assert.ok(!/\bfzf\b/.test(source))
assert.ok(!source.includes('mirrors.ustc.edu.cn'))
assert.ok(!source.includes('mirrors.tuna.tsinghua.edu.cn'))

assert.match(brewMirror, /deployBrewRuntime/)
assert.match(brewMirror, /lib\/mirror-menu\.js/)
assert.match(brewMirror, /lib\/menu-select\.js/)
assert.match(brewPm, /applySelectedMirror|ensureBrewZprofile/)
assert.match(brewPm, /USE_BREW_MIRROR/)
assert.match(brewPm, /canOpenTerminal/)
assert.match(brewPm, /findBrewBinary/)
assert.ok(!brewPm.includes('command -v brew'))
assert.ok(!/if\s*\(\s*!process\.stdin\.isTTY\s*\)/.test(brewPm))

assert.match(installSh, /REPO_ZIP|download_zip_repo|fetch_repo/)

const syncLocals = manifest.sync.toRepo.map((item) => item.local)
// Runtime helpers are deployed by pm, not part of config sync.
assert.ok(!syncLocals.some((local) => String(local).includes('.config/homebrew/mirror-cli.zsh')))
assert.ok(!syncLocals.some((local) => String(local).includes('.config/homebrew/mirrors.tsv')))
assert.ok(!syncLocals.some((local) => String(local).includes('.config/homebrew/lib/mirror-menu.js')))
assert.ok(!syncLocals.some((local) => String(local).includes('manage.zsh')))
assert.ok(!syncLocals.some((local) => String(local).includes('brew-mirror.zsh')))
assert.equal(manifest.brewfile, 'configs/macos/brew/Brewfile')
assert.equal(manifest.brewMirrorCatalog, 'configs/macos/brew/mirrors.tsv')

const menuCli = fs.readFileSync(path.join(root, 'runtime/brew/mirror-menu.js'), 'utf8')
assert.match(menuCli, /runMenuSelect/)
assert.match(menuCli, /MENU_SELECT_OUT/)
assert.match(menuCli, /use-homebrew-mirrors-v1/)
assert.ok(menuCli.includes('.replace(/\\r\\n/g'))

const bashProbe = spawnSync('bash', ['-c', 'exit 0'], { encoding: 'utf8' })
if (bashProbe.error || bashProbe.status !== 0) {
  console.log('brew/mirror.test.mjs: ok (contracts; skip e2e — bash unavailable)')
  process.exit(0)
}

// End-to-end wrapper behavior in a temp HOME.
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'use-brew-mirror-'))
const bin = path.join(temp, 'bin')
const homebrewDir = path.join(temp, '.config/homebrew')
fs.mkdirSync(bin)
fs.mkdirSync(homebrewDir, { recursive: true })
// Normalize CRLF so bash/zsh header checks work on Windows checkouts.
fs.writeFileSync(path.join(homebrewDir, 'mirrors.tsv'), fs.readFileSync(catalog, 'utf8').replace(/\r\n/g, '\n'))
fs.copyFileSync(helper, path.join(homebrewDir, 'mirror-cli.zsh'))
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

brew mirror ustc >/dev/null
test "$USE_HOMEBREW_MIRROR" = ustc
test "$HOMEBREW_API_DOMAIN" = "https://mirrors.ustc.edu.cn/homebrew-bottles/api"

brew mirror tuna >/dev/null
test "$USE_HOMEBREW_MIRROR" = tuna
test "$HOMEBREW_BREW_GIT_REMOTE" = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"

unset USE_HOMEBREW_MIRROR
rm -f "$XDG_CONFIG_HOME/homebrew/mirror.zsh"
brew mirror official >/dev/null
test "$USE_HOMEBREW_MIRROR" = official
test -z "\${HOMEBREW_API_DOMAIN+x}"
brew mirror status | grep -q "Active Homebrew mirror: official"

brew shellenv | grep -q '/fake/homebrew/bin'

if [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
  OLD_PATH="$PATH"
  export PATH=/usr/bin:/bin
  unset -f brew 2>/dev/null || true
  source "$HELPER"
  ! _brew_mirror_find_brew >/dev/null 2>&1
  ec=0
  brew update >/dev/null 2>&1 || ec=$?
  test "$ec" -eq 127
  export PATH="$OLD_PATH"
fi

mkdir -p "$HOME/.zsh/functions"
printf '# legacy\\n' > "$HOME/.zsh/functions/brew-mirror.zsh"
printf '# legacy-home\\n' > "$XDG_CONFIG_HOME/homebrew/manage.zsh"
printf '# legacy-prev\\n' > "$XDG_CONFIG_HOME/homebrew/brew-mirror.zsh"
source "$HELPER"
test ! -e "$HOME/.zsh/functions/brew-mirror.zsh"
test ! -e "$XDG_CONFIG_HOME/homebrew/manage.zsh"
test ! -e "$XDG_CONFIG_HOME/homebrew/brew-mirror.zsh"
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
assert.match(profile, /mirror-cli\.zsh/)
assert.match(profile, /eval "\$\([^)]+\/brew shellenv\)"/)
assert.ok(!profile.includes('manage.zsh'))

const persisted = fs.readFileSync(path.join(temp, '.config/homebrew/mirror.zsh'), 'utf8')
assert.match(persisted, /export USE_HOMEBREW_MIRROR=official/)
assert.match(persisted, /unset HOMEBREW_API_DOMAIN/)

fs.writeFileSync(path.join(temp, '.zprofile'), '# >>> use-homebrew\nexport KEEP_THIS_SETTING=yes\n')
const refuse = spawnSync('bash', ['-c', 'source "$HELPER"; brew mirror tuna'], {
  encoding: 'utf8',
  env: {
    ...process.env,
    HELPER: helper,
    HOME: temp,
    PATH: `${bin}:${process.env.PATH}`,
    XDG_CONFIG_HOME: path.join(temp, '.config'),
  },
})
assert.notEqual(refuse.status, 0)
assert.match(String(refuse.stderr || ''), /incomplete/)

fs.rmSync(temp, { recursive: true, force: true })
console.log('brew/mirror.test.mjs: ok')
