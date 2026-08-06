import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '../../../..')
const helper = path.join(root, 'scripts/macos/brew/mirror/manage.zsh')
const catalog = path.join(root, 'configs/macos/brew/mirrors.tsv')
const source = fs.readFileSync(helper, 'utf8')
const installer = fs.readFileSync(path.join(root, 'scripts/macos/brew/install.sh'), 'utf8')
const installSh = fs.readFileSync(path.join(root, 'install.sh'), 'utf8')
const initSh = fs.readFileSync(path.join(root, 'scripts/macos/init.sh'), 'utf8')
const dispatch = fs.readFileSync(path.join(root, 'scripts/_dispatch.mjs'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'scripts/macos/_manifest.json'), 'utf8'))
const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8')

assert.match(source, /mirrors\.tsv/)
assert.match(source, /use-homebrew-mirrors-v1/)
assert.match(source, /_brew_mirror_lookup/)
assert.match(source, /_brew_mirror_can_prompt/)
assert.match(source, /^brew\(\) \{/m)
assert.match(source, /_brew_mirror_cli/)
assert.match(source, /Usage: brew mirror/)
assert.match(source, /type -P brew|whence -p brew/)
assert.match(source, /_brew_mirror_find_brew/)
assert.match(source, /Homebrew not found/)
assert.ok(!/command brew "\$@"/.test(source))
assert.ok(!/_brew_mirror_aligned_choices/.test(source))
assert.ok(!/\bfzf\b/.test(source))
assert.ok(!/_brew_mirror_menu_script/.test(source))
assert.ok(!/formatAlignedChoices/.test(source))
assert.ok(!/MENU_SELECT_INITIAL/.test(source))
assert.ok(!/MENU_SELECT_MODULE/.test(source))
assert.ok(!/node --input-type=module/.test(source))
assert.match(source, /_brew_mirror_menu_cli/)
assert.match(source, /menu\.mjs/)
assert.match(source, /manage\.zsh/)
assert.match(source, /brew-mirror\.zsh/)
assert.match(source, /Node\.js is required/)
assert.match(installer, /lib\/menu\.mjs/)
assert.match(installer, /lib\/menu-select\.mjs/)
assert.match(installer, /lib\/tty-term\.mjs/)
assert.match(installer, /manage\.zsh/)
assert.match(installer, /mirror\/menu\.mjs/)
assert.match(installer, /if _brew_mirror_find_brew/)
assert.ok(!/if command -v brew/.test(installer))
assert.match(initSh, /if ! _brew_mirror_find_brew/)
assert.ok(!/if ! command -v brew/.test(initSh))
const runBrew = fs.readFileSync(path.join(root, 'scripts/macos/brew/run.sh'), 'utf8')
assert.match(runBrew, /brew_bin=\$\(_brew_mirror_find_brew\)/)
assert.match(runBrew, /manage\.zsh/)
assert.ok(!/if ! command -v brew/.test(runBrew))
assert.match(runBrew, /exec "\$brew_bin"/)
assert.ok(!source.includes('mirrors.ustc.edu.cn'))
assert.ok(!source.includes('mirrors.tuna.tsinghua.edu.cn'))

assert.match(installer, /deploy_homebrew_runtime/)
assert.match(installer, /apply_selected_mirror/)
assert.match(installer, /brewMirrorCatalog/)
assert.match(installer, /USE_BREW_MIRROR/)
assert.match(installer, /_brew_mirror_remove_legacy/)
assert.ok(!installer.includes('USE_HOMEBREW_MIRROR:-'))
assert.ok(!installer.includes('mirror_exports'))
assert.ok(!/source\s+"?\$\(expand_path/.test(installer))
assert.ok(!/\. "\$\{HOME\}\/\.zprofile"/.test(installer))

assert.match(installSh, /bash scripts\/macos\/brew\/install\.sh\b/)
assert.ok(!/brew-install\.sh\s+"\$\{USE_/.test(installSh))
assert.ok(!installSh.includes('brew-install.sh ustc'))
assert.ok(!/\. "\$\{HOME\}\/\.zprofile"/.test(installSh))
assert.match(initSh, /_brew_mirror_apply_env/)
assert.match(initSh, /_brew_mirror_remove_legacy/)
assert.match(initSh, /brew\/run\.sh/)
assert.match(initSh, /manage\.zsh/)
assert.match(dispatch, /writeBrewLiteBackup/)
assert.match(dispatch, /brew\/run\.sh/)
assert.match(dispatch, /brew\/install\.sh/)
assert.match(dispatch, /brew\/generated\.mjs/)
assert.match(source, /_brew_mirror_persisted_id/)
assert.match(source, /_brew_mirror_remove_legacy/)
assert.match(source, /Canceled/)
assert.match(source, /Already active/)
assert.match(source, /ec == 130/)
assert.match(source, /_brew_mirror_ensure_profile/)
assert.ok(!/^brew-mirror\(\)/m.test(source))
assert.match(readme, /brew mirror\s+# 交互/)
assert.match(readme, /brew mirror status/)
assert.match(readme, /manage\.zsh/)
assert.match(readme, /menu\.mjs/)
assert.ok(!readme.includes('brew-mirror status'))
assert.ok(!readme.includes('brew-mirror.zsh'))
const configSync = fs.readFileSync(path.join(root, 'scripts/macos/config-sync.sh'), 'utf8')
assert.match(configSync, /_brew_mirror_remove_legacy/)
assert.match(configSync, /manage\.zsh/)

const syncLocals = manifest.sync.toRepo.map((item) => item.local)
const syncRepos = manifest.sync.toRepo.map((item) => item.repo)
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/manage.zsh')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/mirrors.tsv')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/menu.mjs')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/menu-select.mjs')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/tty-term.mjs')))
assert.ok(syncRepos.some((repo) => String(repo).includes('scripts/macos/brew/mirror/manage.zsh')))
assert.ok(syncRepos.some((repo) => String(repo).includes('scripts/macos/brew/mirror/menu.mjs')))
assert.ok(syncRepos.some((repo) => String(repo).includes('configs/macos/brew/mirrors.tsv')))
assert.ok(!syncLocals.some((local) => String(local).includes('brew-mirror.zsh')))

const menuCli = fs.readFileSync(path.join(root, 'scripts/macos/brew/mirror/menu.mjs'), 'utf8')
assert.match(menuCli, /formatAlignedChoices/)
assert.match(menuCli, /runMenuSelect/)
assert.match(menuCli, /use-homebrew-mirrors-v1/)
assert.match(menuCli, /invalid catalog row/)
assert.match(menuCli, /process\.exit\(130\)/)
assert.match(menuCli, /menu-select\.mjs/)

assert.equal(manifest.brewfile, 'configs/macos/brew/Brewfile')
assert.equal(manifest.brewfileLite, 'configs/macos/brew/Brewfile.lite')
assert.equal(manifest.brewMirrorCatalog, 'configs/macos/brew/mirrors.tsv')

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'use-brew-mirror-'))
const bin = path.join(temp, 'bin')
const homebrewDir = path.join(temp, '.config/homebrew')
fs.mkdirSync(bin)
fs.mkdirSync(homebrewDir, { recursive: true })
fs.copyFileSync(catalog, path.join(homebrewDir, 'mirrors.tsv'))
fs.copyFileSync(helper, path.join(homebrewDir, 'manage.zsh'))
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

# Selecting official with no active env must still persist (not treat as no-op).
unset USE_HOMEBREW_MIRROR
rm -f "$XDG_CONFIG_HOME/homebrew/mirror.zsh"
brew mirror official >/dev/null
test "$USE_HOMEBREW_MIRROR" = official
test -z "\${HOMEBREW_API_DOMAIN+x}"
test -z "\${HOMEBREW_BOTTLE_DOMAIN+x}"
test -z "\${HOMEBREW_BREW_GIT_REMOTE+x}"
brew mirror status | grep -q "Active Homebrew mirror: official"

# Non-mirror brew calls still reach the real binary via _brew_mirror_find_brew.
brew shellenv | grep -q '/fake/homebrew/bin'

# Wrapper must not make a missing binary look installed.
OLD_PATH="$PATH"
export PATH=/usr/bin:/bin
unset -f brew 2>/dev/null || true
# Re-source so brew() exists but type -P brew / standard prefixes miss.
source "$HELPER"
command -v brew >/dev/null  # function is visible
! _brew_mirror_find_brew >/dev/null 2>&1
ec=0
brew update >/dev/null 2>&1 || ec=$?
test "$ec" -eq 127
export PATH="$OLD_PATH"

# Legacy overrides are removed when the helper is sourced / applied.
mkdir -p "$HOME/.zsh/functions"
printf '# legacy\\n' > "$HOME/.zsh/functions/brew-mirror.zsh"
printf '# legacy-home\\n' > "$XDG_CONFIG_HOME/homebrew/brew-mirror.zsh"
source "$HELPER"
test ! -e "$HOME/.zsh/functions/brew-mirror.zsh"
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
assert.equal((profile.match(/# <<< use-homebrew/g) || []).length, 1)
assert.match(profile, /mirror\.zsh/)
assert.match(profile, /manage\.zsh/)
assert.ok(!profile.includes('brew-mirror.zsh'))
assert.match(profile, /shellenv/)
// Profile must call the real brew binary, not the shell wrapper name alone.
assert.match(profile, /eval "\$\([^)]+\/brew shellenv\)"/)

const persisted = fs.readFileSync(path.join(temp, '.config/homebrew/mirror.zsh'), 'utf8')
assert.match(persisted, /export USE_HOMEBREW_MIRROR=official/)
assert.match(persisted, /unset HOMEBREW_API_DOMAIN/)
assert.match(persisted, /Managed by brew mirror/)

// Incomplete markers must refuse to modify the profile.
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
console.log('macos/brew/mirror/test.mjs: ok')
