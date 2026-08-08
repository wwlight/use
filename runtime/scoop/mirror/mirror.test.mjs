import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '../../..')
const read = (path) => readFileSync(resolve(root, path), 'utf8')

const common = JSON.parse(read('manifests/common.json'))
const mirrorIds = common.githubAccel.mirrors.map(({ id }) => id)
const mirrorPrefixes = common.githubAccel.mirrors.map(({ prefix }) => prefix)
assert.equal(new Set(mirrorIds).size, mirrorIds.length)
assert.equal(new Set(mirrorPrefixes).size, mirrorPrefixes.length)
assert.ok(mirrorIds.includes(common.githubAccel.default))

// Windows PowerShell 5.1 footguns (one-click / scoop scripts run under 5.1).
const ps51Sources = [
  'install.ps1',
  'runtime/scoop/accel.ps1',
  'runtime/scoop/install.ps1',
  'runtime/scoop/utils.ps1',
  'runtime/scoop/deploy.ps1',
  'runtime/scoop/import-backup.ps1',
  'runtime/scoop/mirror/hook.ps1',
  'runtime/scoop/mirror/shared.ps1',
  'runtime/scoop/services/manage.ps1',
  'configs/windows/scoop/scoop.ps1',
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

const installer = read('runtime/scoop/accel.ps1')
const scoopInstall = read('runtime/scoop/install.ps1')
const utilsPs = read('runtime/scoop/utils.ps1')
const rootInstall = read('install.ps1')

// Quiet one-click logging surface.
assert.match(utilsPs, /function Test-ScoopQuietPm/)
assert.match(utilsPs, /function Write-Detail/)
assert.match(utilsPs, /function Invoke-Spin/)
assert.match(utilsPs, /function Write-SpinDone/)
assert.match(utilsPs, /ScoopSpinActive/)
assert.match(utilsPs, /Write-Host "   \$Message"/)
assert.match(rootInstall, /USE_QUIET_INSTALL[\s\S]*finally/)
assert.match(scoopInstall, /Complete-ScoopAccelSetup/)
assert.match(scoopInstall, /Setting up Scoop/)
assert.match(scoopInstall, /-Done \{ "Scoop ready/)
assert.match(read('src/core/log.js'), /function nestLine/)
assert.ok(!/from ["']\.\.\/core\/log\.js["']/.test(read('src/lib/menu-select.js')))

// Enable deploys only; install.ps1 owns hook / bootstrap / buckets / aria2.
const enableAccel = installer.slice(installer.indexOf('function Enable-ScoopAccel'))
assert.match(enableAccel, /Install-ScoopMirrorAccelFiles/)
assert.ok(!/Install-ScoopDownloadHook/.test(enableAccel))
assert.ok(!/Set-ScoopBucketMirrors/.test(enableAccel))
assert.ok(!/Install-ScoopAria2Accel/.test(enableAccel))
assert.match(scoopInstall, /Enable-ScoopAccel/)
assert.match(scoopInstall, /Install-ScoopDownloadHook/)
assert.match(scoopInstall, /Install-ScoopBootstrapApps/)
assert.match(scoopInstall, /Ensure-ScoopGitRepositories/)
assert.match(scoopInstall, /Set-ScoopBucketMirrors/)
assert.match(scoopInstall, /Install-ScoopAria2Accel/)

// Main bucket must become mirrored-git before scoop update.
const ensureGit = installer.match(/function Ensure-ScoopGitRepositories[\s\S]*?\nfunction /)?.[0] || ''
const ensureMainCallAt = ensureGit.indexOf('Ensure-ScoopMainBucketGit -ActivePrefix')
const scoopUpdateCmdAt = ensureGit.search(/Invoke-QuietHost \{ scoop update/)
const completeCoreAt = ensureGit.indexOf('Complete-ScoopCoreGitConversion')
assert.ok(ensureMainCallAt > 0 && scoopUpdateCmdAt > ensureMainCallAt)
assert.ok(completeCoreAt > scoopUpdateCmdAt)

// USE_ACCEL only auto-selects when non-interactive.
const resolveMirror = installer.match(/function Resolve-ScoopMirrorSelection[\s\S]*?\nfunction /)?.[0] || ''
assert.match(resolveMirror, /USE_ACCEL/)
assert.match(resolveMirror, /Test-InteractivePrompt/)
assert.ok(
  /if\s*\([^)]*USE_ACCEL[\s\S]*?-not\s*\(Test-InteractivePrompt\)/.test(resolveMirror)
  || /hintFromEnv[\s\S]*?-not\s*\(Test-InteractivePrompt\)[\s\S]*\$Choice\s*=\s*\$hintFromEnv/.test(resolveMirror),
)

// Installer bootstrap must not pollute ActivePrefix via Write-Output.
const bootstrap = installer.match(/function Invoke-ScoopInstallScriptWithFallback[\s\S]*?\nfunction /)?.[0] || ''
assert.match(bootstrap, /\[ref\]\$OutPrefix/)
assert.match(bootstrap, /Invoke-QuietHost/)
assert.match(bootstrap, /\$OutPrefix\.Value\s*=\s*\$successPrefix/)
assert.ok(!/return \$successPrefix/.test(bootstrap))

assert.match(installer, /function New-ScoopMirroredImportFile/)
assert.ok(!/raw\.githubusercontent\.com/.test(installer.match(/function ConvertTo-MirrorUrl[\s\S]*?\n}/)?.[0] || ''))
assert.ok(!existsSync(resolve(root, 'runtime/scoop/mirror/manage.ps1')))

// Download filter smudge/clean behavior.
const filter = resolve(root, 'runtime/scoop/mirror/cli.js')
const tracked = Buffer.from("function Start-Download {\n  'upstream'\n}\n", 'utf8')
const hooked = Buffer.concat([
  tracked,
  Buffer.from('\n# >>> scoop-mirror\n. "$env:SCOOP\\config\\scoop-mirror\\hook.ps1"\n# <<< scoop-mirror\n', 'utf8'),
])
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
assert.equal(hasCurrentHookMarkers(Buffer.from(
  '\n# >>> scoop-mirror\n. "$env:SCOOP\\config\\scoop-mirror\\hook.ps1"\n# <<< scoop-mirror\n',
  'utf8',
)), true)
assert.equal(hasCurrentHookMarkers(Buffer.from(
  '\n# >>> scoop-mirror-accel\n. "$env:SCOOP\\config\\mirror-accel.ps1"\n# <<< scoop-mirror-accel\n',
  'utf8',
)), false)

// Shell helpers: critical contracts only.
const scoopPs = read('configs/windows/scoop/scoop.ps1')
assert.match(scoopPs, /scoop-mirror/)
assert.match(scoopPs, /scoop-services\\manage\.ps1/)
// Do not bind ValueFromRemainingArguments under -File (empties $args).
assert.ok(!/\[Parameter\([^\]]*ValueFromRemainingArguments/.test(read('runtime/scoop/services/manage.ps1')))
const importBackup = read('runtime/scoop/import-backup.ps1')
assert.match(importBackup, /New-ScoopMirroredImportFile/)
assert.match(importBackup, /error\.log/)
assert.match(importBackup, /Invoke-QuietHost -Capture/)
assert.match(utilsPs, /\[System\.Collections\.IList\]\$Capture/)

// One-click order: node → fetch → pm.
assert.match(rootInstall, /Ensure-NodeRuntime/)
assert.match(rootInstall, /Fetch-UseRepository|Expand-UseZipRepository/)
assert.match(rootInstall, /Invoke-UseCli -CliArgs \$pmArgs/)
assert.match(rootInstall, /SYNC_SKIP_PM_HELPERS\s*=\s*'1'/)
assert.ok(!/Invoke-UseCli @\('init', '--'/.test(rootInstall))
assert.match(rootInstall, /function Get-UrlHostLabel/)

const windowsManifest = JSON.parse(read('manifests/windows.json'))
const syncLocals = windowsManifest.sync.toRepo.map((item) => String(item.local))
assert.ok(syncLocals.some((local) => local.includes('scoop-mirror/hook.ps1')))
assert.ok(syncLocals.some((local) => local.includes('scoop-mirror/cli.js')))
assert.ok(!syncLocals.some((local) => local.includes('scoop-mirror/manage.ps1')))
assert.equal(windowsManifest.scoopBackup, 'configs/windows/scoop/backup.json')

console.log('scoop/mirror/mirror.test.mjs: ok')
