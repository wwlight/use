import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '../..')
const helper = path.join(root, 'runtime/brew/mirror-cli.zsh')
const catalog = path.join(root, 'configs/macos/brew/mirrors.tsv')
const source = fs.readFileSync(helper, 'utf8')
const brewPm = fs.readFileSync(path.join(root, 'src/pm/brew.js'), 'utf8')
const brewMirror = fs.readFileSync(path.join(root, 'src/pm/brew-mirror.js'), 'utf8')
const installSh = fs.readFileSync(path.join(root, 'install.sh'), 'utf8')
const cliTs = fs.readFileSync(path.join(root, 'src/cli.js'), 'utf8')
const initTs = fs.readFileSync(path.join(root, 'src/commands/init.js'), 'utf8')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifests/macos.json'), 'utf8'))
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
assert.match(source, /mirror-menu\.js/)
assert.match(source, /lib\/mirror-menu\.js/)
assert.match(source, /mirror-cli\.zsh/)
assert.match(source, /manage\.zsh/) // legacy cleanup
assert.match(source, /brew-mirror\.zsh/) // legacy cleanup
assert.match(source, /Node\.js is required/)
assert.match(brewMirror, /lib\/mirror-menu\.js/)
assert.match(brewMirror, /lib\/menu-select\.js/)
assert.match(brewPm, /runMenuSelect/)
assert.ok(!/choice=\$\(node "\$SCRIPT_DIR\/lib\/menu-select\.mjs"/.test(brewPm))
assert.match(initTs, /runMenuSelect|formatAlignedChoices/)
assert.match(brewPm, /formatAlignedChoices/)
assert.ok(!/mirrorMenuItems|profileMenuItems/.test(brewPm))
assert.ok(!/profileMenuItems/.test(initTs))
assert.match(cliTs, /markCliInteractive/)
assert.match(cliTs, /runBrewPmCommand/)
assert.match(cliTs, /runInitCommand|runBackupCommand|runSyncCommand/)
assert.ok(!/process\.stdin\.isTTY \|\| process\.stdout\.isTTY/.test(cliTs))
assert.match(source, /MENU_SELECT_OUT/)
assert.ok(!/choice=\$\(node "\$menu_js"/.test(source))
assert.match(brewMirror, /lib\/string-width\.js/)
assert.match(brewMirror, /lib\/tty-term\.js/)
assert.match(brewMirror, /mirror-cli\.zsh/)
assert.match(brewMirror, /mirror-menu\.js/)
assert.ok(!/mirror\/menu\.js/.test(brewMirror))
assert.match(brewPm, /findBrewBinary/)
assert.ok(!/if command -v brew/.test(brewPm))
assert.match(initTs, /runBrew\(/)
assert.match(brewPm, /export function runBrew/)
assert.match(brewPm, /findBrewBinary/)
assert.ok(!brewPm.includes('command -v brew'))
assert.ok(!source.includes('mirrors.ustc.edu.cn'))
assert.ok(!source.includes('mirrors.tuna.tsinghua.edu.cn'))

assert.match(brewMirror, /deployBrewRuntime/)
assert.match(brewPm, /applySelectedMirror|ensureBrewZprofile/)
assert.match(brewMirror, /brewMirrorCatalog/)
assert.match(brewPm, /USE_BREW_MIRROR/)
assert.match(brewPm, /canOpenTerminal/)
assert.ok(!/if\s*\(\s*!process\.stdin\.isTTY\s*\)/.test(brewPm))
assert.match(brewMirror, /removeBrewMirrorLegacy/)
assert.ok(!brewPm.includes('USE_HOMEBREW_MIRROR:-'))
assert.ok(!brewPm.includes('mirror_exports'))
assert.ok(!/source\s+"?\$\(expand_path/.test(brewPm))
assert.ok(!/\. "\$\{HOME\}\/\.zprofile"/.test(brewPm))

assert.match(installSh, /run_cli pm\b|node "\$INSTALL_DIR\/src\/cli\.js" pm\b/)
assert.match(installSh, /SYNC_INTERACTIVE=1/)
assert.match(installSh, /SYNC_SKIP_PM_HELPERS=1/)
assert.match(installSh, /run_cli init|src\/cli\.js/)
assert.match(installSh, /REPO_ZIP|download_zip_repo|fetch_repo/)
assert.match(installSh, /%Y%m%d%H%M%S/, 'sibling dir is use + timestamp, no hyphens')
assert.match(installSh, /target="\$\{base\}\$\{ts\}"/)
assert.ok(!/brew-install\.sh\s+"\$\{USE_/.test(installSh))
assert.ok(!installSh.includes('brew-install.sh ustc'))
assert.ok(!/\. "\$\{HOME\}\/\.zprofile"/.test(installSh))
assert.match(cliTs, /runBrewPmCommand/)
assert.match(cliTs, /runBackupCommand/)
const backupTs = fs.readFileSync(path.join(root, 'src/commands/backup.js'), 'utf8')
assert.match(backupTs, /writeBrewLiteBackup/)
assert.match(backupTs, /runBrew/)
assert.match(source, /_brew_mirror_persisted_id/)
assert.match(source, /_brew_mirror_remove_legacy/)
assert.match(source, /Already active/)
assert.match(source, /return "\$ec"/)
assert.match(source, /mirror-menu\.js already printed Canceled/)
assert.ok(!/printf 'Canceled\\n'/.test(source))
assert.match(source, /_brew_mirror_ensure_profile/)
assert.ok(!/^brew-mirror\(\)/m.test(source))
assert.match(readme, /brew mirror\s+# 交互/)
assert.match(readme, /brew mirror status/)
assert.match(readme, /mirror-cli\.zsh/)
assert.match(readme, /mirror-menu\.js/)
assert.ok(!readme.includes('brew-mirror status'))
assert.ok(!readme.includes('manage.zsh'))
assert.match(brewMirror, /removeBrewMirrorLegacy/)
assert.match(brewMirror, /manage\.zsh/) // legacy cleanup target

const syncLocals = manifest.sync.toRepo.map((item) => item.local)
const syncRepos = manifest.sync.toRepo.map((item) => item.repo)
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/mirror-cli.zsh')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/mirrors.tsv')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/mirror-menu.js')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/menu-select.js')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/string-width.js')))
assert.ok(syncLocals.some((local) => String(local).includes('.config/homebrew/lib/tty-term.js')))
assert.ok(syncRepos.some((repo) => String(repo).includes('src/lib/string-width.js')))
assert.ok(syncRepos.some((repo) => String(repo).includes('runtime/brew/mirror-cli.zsh')))
assert.ok(syncRepos.some((repo) => String(repo).includes('runtime/brew/mirror-menu.js')))
assert.ok(syncRepos.some((repo) => String(repo).includes('configs/macos/brew/mirrors.tsv')))
assert.ok(!syncLocals.some((local) => String(local).includes('manage.zsh')))
assert.ok(!syncLocals.some((local) => String(local).includes('brew-mirror.zsh')))
assert.ok(!syncLocals.some((local) => String(local).includes('/lib/menu.js')))

const menuCli = fs.readFileSync(path.join(root, 'runtime/brew/mirror-menu.js'), 'utf8')
assert.match(menuCli, /findRepoRoot|manifests.*common\.json/)
assert.match(menuCli, /src\/lib\/menu-select\.js|src.*lib.*menu-select/)
assert.ok(!menuCli.includes('../../src/lib/menu-select.js'))
assert.ok(fs.existsSync(path.join(root, 'src/lib/menu-select.js')))
assert.match(menuCli, /formatAlignedChoices/)
assert.match(menuCli, /runMenuSelect/)
assert.match(menuCli, /MENU_SELECT_OUT/)
assert.match(menuCli, /Canceled/)
assert.match(menuCli, /use-homebrew-mirrors-v1/)
assert.match(menuCli, /invalid catalog row/)
assert.match(menuCli, /process\.exit\(130\)/)
assert.match(menuCli, /menu-select\.js/)

assert.equal(manifest.brewfile, 'configs/macos/brew/Brewfile')
assert.equal(manifest.brewfileLite, 'configs/macos/brew/Brewfile.lite')
assert.equal(manifest.brewMirrorCatalog, 'configs/macos/brew/mirrors.tsv')

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'use-brew-mirror-'))
const bin = path.join(temp, 'bin')
const homebrewDir = path.join(temp, '.config/homebrew')
fs.mkdirSync(bin)
fs.mkdirSync(homebrewDir, { recursive: true })
fs.copyFileSync(catalog, path.join(homebrewDir, 'mirrors.tsv'))
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
# Skip when a real Homebrew install exists at the standard prefixes — find_brew
# intentionally falls back to those paths even if PATH is empty.
if [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
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
fi

# Legacy overrides are removed when the helper is sourced / applied.
mkdir -p "$HOME/.zsh/functions"
printf '# legacy\\n' > "$HOME/.zsh/functions/brew-mirror.zsh"
printf '# legacy-home\\n' > "$XDG_CONFIG_HOME/homebrew/manage.zsh"
printf '# legacy-prev\\n' > "$XDG_CONFIG_HOME/homebrew/brew-mirror.zsh"
source "$HELPER"
test ! -e "$HOME/.zsh/functions/brew-mirror.zsh"
test ! -e "$XDG_CONFIG_HOME/homebrew/manage.zsh"
test ! -e "$XDG_CONFIG_HOME/homebrew/brew-mirror.zsh"
test -e "$XDG_CONFIG_HOME/homebrew/mirror-cli.zsh"
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
assert.match(profile, /mirror-cli\.zsh/)
assert.match(profile, /XDG_CONFIG_HOME:-\$HOME\/\.config/)
assert.ok(!profile.includes(`${temp}/.config/homebrew`))
assert.ok(!profile.includes('manage.zsh'))
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
console.log('brew/mirror.test.mjs: ok')
