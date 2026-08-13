import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const read = (path) => readFileSync(resolve(root, path), 'utf8')

const common = JSON.parse(read('manifests/common.json'))
const mirrorIds = common.githubAccel.mirrors.map(({ id }) => id)
const mirrorPrefixes = common.githubAccel.mirrors.map(({ prefix }) => prefix)
assert.equal(new Set(mirrorIds).size, mirrorIds.length)
assert.equal(new Set(mirrorPrefixes).size, mirrorPrefixes.length)
assert.ok(mirrorIds.includes(common.githubAccel.default))

// Windows PowerShell 5.1 footguns (helpers under runtime/scoop/bootstrap + deployed PS).
const ps51Sources = [
  'install.ps1',
  'runtime/scoop/bootstrap/apply.ps1',
  'runtime/scoop/bootstrap/urls.ps1',
  'runtime/scoop/bootstrap/install.ps1',
  'runtime/scoop/bootstrap/git-convert.ps1',
  'runtime/scoop/bootstrap/entry.ps1',
  'runtime/scoop/bootstrap/utils.ps1',
  'runtime/scoop/mirror/hook.ps1',
  'runtime/scoop/mirror/shared.ps1',
  'runtime/scoop/services/cli.ps1',
  'runtime/scoop/scoop.ps1',
]
for (const rel of ps51Sources) {
  const src = read(rel)
  assert.ok(!/^[ \t]*\|/m.test(src), `${rel}: leading '|' breaks PS 5.1`)
  assert.ok(!/^[ \t]*(-and|-or)\b/m.test(src), `${rel}: leading -and/-or breaks PS 5.1`)
  assert.ok(!/\?\?/.test(src), `${rel}: ?? is PowerShell 7+`)
  assert.ok(!/\?\.\w/.test(src), `${rel}: ?. is PowerShell 7+`)
  assert.ok(!/(?<!\|)&\&(?!&)/.test(src), `${rel}: && statement separator is PowerShell 7+`)
  assert.ok(!/(?<!\|)\|\|(?!\|)/.test(src), `${rel}: || statement separator is PowerShell 7+`)
  assert.ok(!/-AsHashtable\b/.test(src), `${rel}: ConvertFrom-Json -AsHashtable is PowerShell 6+`)
  assert.ok(!/-Parallel\b/.test(src), `${rel}: ForEach -Parallel is PowerShell 7+`)
}

const scoopIndex = read('src/pm/scoop/index.js')
const scoopMirror = read('src/pm/scoop/mirror.js')
const scoopDeploy = read('src/pm/scoop/deploy.js')
const scoopImport = read('src/pm/scoop/import.js')
const entryPs = read('runtime/scoop/bootstrap/entry.ps1')
const applyPs = read('runtime/scoop/bootstrap/apply.ps1')
const utilsPs = read('runtime/scoop/bootstrap/utils.ps1')
const rootInstall = read('install.ps1')

assert.match(scoopIndex, /resolveScoopMirror/)
assert.match(scoopIndex, /deployScoopRuntime/)
assert.match(scoopIndex, /runtime['"`].*scoop['"`].*bootstrap|runtime\/scoop\/bootstrap/)
assert.match(scoopIndex, /-Phase/)
assert.match(scoopMirror, /USE_ACCEL/)
assert.match(scoopMirror, /canOpenTerminal|SYNC_INTERACTIVE/)
assert.match(scoopDeploy, /runtime\/scoop/)
assert.match(scoopDeploy, /scoopConfigDir|~\.config\/scoop|\.config['"`].*scoop/)
assert.match(scoopImport, /writeMirroredImportFile|convertToMirrorUrl/)
assert.match(entryPs, /USE_SCOOP_BOOTSTRAP_OUT/)
assert.match(entryPs, /Complete-ScoopMirrorSetup|Enable-ScoopMirror/)
assert.match(applyPs, /Enable-ScoopMirror/)
assert.ok(!/Install-ScoopMirrorAccelFiles|Install-ScoopServicesFiles|Resolve-ScoopMirrorSelection|New-ScoopMirroredImportFile/.test(applyPs + entryPs + read('runtime/scoop/bootstrap/urls.ps1')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/bootstrap/deploy.ps1')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/bootstrap/mirror-url.ps1')))
assert.match(utilsPs, /Join-Path \$PSScriptRoot '\.\.\/\.\.\/\.\.'/)
assert.match(utilsPs, /function Get-ScoopConfigDir/)
assert.ok(!existsSync(resolve(root, 'src/pm/scoop/ps')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/pm')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/deploy')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/ps')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/bootstrap/entry.ps1')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/bootstrap/apply.ps1')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/bootstrap/urls.ps1')))
assert.ok(!existsSync(resolve(root, 'src/pm/scoop.js')))
assert.ok(!existsSync(resolve(root, 'src/pm/brew.js')))

// src/pm/scoop is JS-only
for (const name of ['index.js', 'mirror.js', 'deploy.js', 'import.js']) {
  assert.ok(existsSync(resolve(root, 'src/pm/scoop', name)))
  assert.ok(name.endsWith('.js'))
}

// Combined PS surface still holds install/git contracts.
const installer = [
  'runtime/scoop/bootstrap/urls.ps1',
  'runtime/scoop/bootstrap/install.ps1',
  'runtime/scoop/bootstrap/git-convert.ps1',
  'runtime/scoop/bootstrap/apply.ps1',
  'runtime/scoop/bootstrap/entry.ps1',
].map(read).join('\n')
assert.match(installer, /Invoke-ScoopInstallScriptWithFallback/)
assert.match(installer, /Ensure-ScoopGitRepositories/)
assert.match(installer, /Install-ScoopAria2\b/)
assert.match(installer, /USE_SCOOP_ARIA2/)
assert.match(installer, /USE_SCOOP_MIRROR_PROBE/)
assert.match(installer, /Get-ScoopMirrorSettings/)

const ensureGit = installer.match(/function Ensure-ScoopGitRepositories[\s\S]*?\nfunction /)?.[0] || ''
const ensureMainCallAt = ensureGit.indexOf('Ensure-ScoopMainBucketGit -ActivePrefix')
const scoopUpdateCmdAt = ensureGit.search(/Invoke-QuietHost \{ scoop update/)
const completeCoreAt = ensureGit.indexOf('Complete-ScoopCoreGitConversion')
assert.ok(ensureMainCallAt > 0 && scoopUpdateCmdAt > ensureMainCallAt)
assert.ok(completeCoreAt > scoopUpdateCmdAt)

const installFn = installer.match(/function Invoke-ScoopInstallScriptWithFallback[\s\S]*?\nfunction /)?.[0] || ''
assert.match(installFn, /\[ref\]\$OutPrefix/)
assert.ok(!/return \$successPrefix/.test(installFn))

// configs keep scoop.zsh only; pwsh scoop.ps1 lives under runtime/ (deployed to ~/.config/scoop).
assert.ok(!existsSync(resolve(root, 'configs/windows/scoop/scoop.ps1')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/scoop.ps1')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/mirror')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/services/cli.ps1')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/shell.ps1')))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/services/manage.ps1')))

const filter = resolve(root, 'runtime/scoop/mirror/cli.js')
const tracked = Buffer.from("function Start-Download {\n  'upstream'\n}\n", 'utf8')
const hookBody = [
  '',
  '# >>> scoop-mirror',
  '$__scoopCfg = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME \'scoop\' } else { Join-Path $env:USERPROFILE \'.config\\scoop\' }',
  '. (Join-Path $__scoopCfg \'mirror\\hook.ps1\')',
  '# <<< scoop-mirror',
  '',
].join('\n')
const hooked = Buffer.concat([tracked, Buffer.from(hookBody, 'utf8')])
function runFilter(mode, input) {
  const result = spawnSync(process.execPath, [filter, mode], { input, encoding: 'buffer' })
  assert.equal(result.status, 0, result.stderr?.toString('utf8') || `${mode} failed`)
  return Buffer.from(result.stdout)
}
assert.deepEqual(runFilter('smudge', tracked), hooked)
assert.deepEqual(runFilter('clean', hooked), tracked)
assert.deepEqual(runFilter('clean', tracked), tracked)
assert.deepEqual(runFilter('smudge', hooked), hooked)

const { hasCurrentHookMarkers } = await import(pathToFileURL(filter).href)
assert.equal(hasCurrentHookMarkers(Buffer.from(hookBody, 'utf8')), true)
assert.equal(hasCurrentHookMarkers(Buffer.from(
  '\n# >>> scoop-mirror\n. "$env:SCOOP\\config\\scoop-mirror\\hook.ps1"\n# <<< scoop-mirror\n',
  'utf8',
)), false)

const scoopPs = read('runtime/scoop/scoop.ps1')
assert.match(scoopPs, /_scoop_config_dir/)
assert.match(scoopPs, /mirror\\cli\.js/)
assert.match(scoopPs, /services\\cli\.ps1/)
assert.ok(!/\[Parameter\([^\]]*ValueFromRemainingArguments/.test(read('runtime/scoop/services/cli.ps1')))

assert.match(rootInstall, /Ensure-NodeRuntime/)
assert.match(rootInstall, /Invoke-UseCli -CliArgs \$pmArgs/)

const windowsManifest = JSON.parse(read('manifests/windows.json'))
const syncRepos = windowsManifest.sync.toRepo.map((item) => String(item.repo))
const syncLocals = windowsManifest.sync.toRepo.map((item) => String(item.local))
// Runtime helpers are deployed by pm, not part of config sync.
assert.ok(!syncRepos.some((repo) => repo.startsWith('runtime/scoop/')))
assert.ok(!syncLocals.some((local) => local.includes('{scoopConfigDir}/')))
assert.ok(!syncLocals.some((local) => local.includes('/shell.ps1')))
assert.ok(!syncLocals.some((local) => local.includes('manage.ps1')))
assert.ok(!syncRepos.some((repo) => repo.includes('/deploy/')))
assert.equal(windowsManifest.scoopBackup, 'configs/windows/scoop/backup.json')

assert.match(read('src/cli.js'), /pm\/scoop\/index\.js/)
assert.match(read('src/cli.js'), /pm\/brew\/index\.js/)
assert.match(read('src/pm/restore.js'), /scoop\/import\.js/)

console.log('runtime/scoop/contract.test.mjs: ok')
