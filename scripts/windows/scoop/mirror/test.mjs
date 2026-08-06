import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '../../../..')
const read = (path) => readFileSync(resolve(root, path), 'utf8')

const common = JSON.parse(read('scripts/common/_manifest.json'))
const mirrorIds = common.githubAccel.mirrors.map(({ id }) => id)
const mirrorPrefixes = common.githubAccel.mirrors.map(({ prefix }) => prefix)

assert.equal(new Set(mirrorIds).size, mirrorIds.length)
assert.equal(new Set(mirrorPrefixes).size, mirrorPrefixes.length)
assert.ok(mirrorIds.includes(common.githubAccel.default))

const installer = read('scripts/windows/scoop/accel.ps1')
assert.match(installer, /Join-Path \$PSScriptRoot 'deploy\.ps1'/)
assert.match(installer, /Invoke-ScoopMirrorAccelFilterInit/)
assert.match(installer, /Install-ScoopMirrorAccelFiles/)
assert.match(installer, /Install-ScoopServicesFiles/)

const deploy = read('scripts/windows/scoop/deploy.ps1')
assert.match(deploy, /mirrors\s*=\s*\$mirrors/)
assert.match(deploy, /scoopRepo\s*=\s*\[string\]\$Accel\.scoopRepo/)
assert.match(deploy, /scoop-mirror/)
assert.match(deploy, /config\\scoop-mirror/)
assert.match(deploy, /Join-Path \$PSScriptRoot 'mirror\\hook\.ps1'|Join-Path \$PSScriptRoot 'mirror\/hook\.ps1'|mirror\\hook\.ps1|mirror\/hook\.ps1/)
assert.match(deploy, /mirror\\shared\.ps1|mirror\/shared\.ps1|'shared\.ps1'/)
assert.match(deploy, /mirror\\manage\.ps1|mirror\/manage\.ps1|'manage\.ps1'/)
assert.match(deploy, /services\\manage\.ps1|services\/manage\.ps1/)
assert.match(deploy, /configs\\windows\\scoop\\scoop\.ps1/)

const hook = read('scripts/windows/scoop/mirror/hook.ps1')
assert.match(hook, /shared\.ps1/)
assert.match(hook, /Start-Download/)
assert.match(hook, /Invoke-CachedAria2Download/)
assert.match(hook, /scoop-mirror\\hook\.ps1/)
assert.ok(!/Invoke-ScoopMirrorManager/.test(hook))
assert.ok(!/\[switch\]\$ManageMirror/.test(hook))

const shared = read('scripts/windows/scoop/mirror/shared.ps1')
assert.match(shared, /function Get-ScoopMirrorAccelConfig/)
assert.match(shared, /function Get-ScoopMirrorAccelCandidates/)
assert.match(shared, /Set-ScoopMirrorBucketRemotes/)
assert.match(shared, /Scoop source: cache/)
assert.match(shared, /return 'direct'/)
assert.match(shared, /GitHub mirror unavailable for this host/)

const manage = read('scripts/windows/scoop/mirror/manage.ps1')
assert.match(manage, /Invoke-ScoopMirrorMenuSelect/)
assert.match(manage, /Invoke-ScoopMirrorManager/)
assert.match(manage, /scoop config scoop_repo \$repo/)
assert.match(manage, /cli\.mjs/)
assert.match(manage, /'switch'/)
assert.match(manage, /Canceled/)
assert.match(manage, /ScoopMirrorCliCode = 130/)
assert.match(manage, /SCOOP_SHELL_INPROCESS/)
assert.match(manage, /shared\.ps1/)

assert.match(hook, /configured GitHub mirrors cannot proxy/)

const filter = resolve(root, 'scripts/windows/scoop/mirror/cli.mjs')
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
const legacy = Buffer.concat([
  tracked,
  Buffer.from('\n# >>> scoop-mirror-accel\n. "$env:SCOOP\\config\\mirror-accel.ps1"\n# <<< scoop-mirror-accel\n', 'utf8'),
])
assert.deepEqual(runFilter('clean', legacy), tracked)

const cliSource = read('scripts/windows/scoop/mirror/cli.mjs')
assert.match(cliSource, /mode === 'switch'/)
assert.match(cliSource, /runSwitchCli/)
assert.match(cliSource, /Canceled/)
assert.match(cliSource, /process\.exit\(130\)/)
assert.match(cliSource, /Already active/)
assert.match(cliSource, /Enter on \*/)
assert.match(cliSource, /scoop_repo/)
assert.match(cliSource, /activePrefix/)
assert.match(cliSource, /formatAlignedChoices/)
assert.match(manage, /dashBase/)
assert.match(cliSource, /function isRepairHealthy/)
assert.match(cliSource, /if \(isRepairHealthy\(/)
assert.match(cliSource, /hasCurrentHookMarkers/)
assert.match(cliSource, /Reject legacy/)
assert.match(hook, /function Test-ScoopMirrorRepairHealthy/)
assert.match(hook, /function Test-ScoopMirrorCurrentHookMarkers/)
assert.match(hook, /Reject legacy/)
assert.match(hook, /scoop-mirror\[\/\\\\\]hook\\.ps1/)
assert.match(hook, /Node repair owns the fast-path/)

const { hasCurrentHookMarkers } = await import(pathToFileURL(filter).href)
const currentHook = Buffer.from(
  '\n# >>> scoop-mirror\n. "$env:SCOOP\\config\\scoop-mirror\\hook.ps1"\n# <<< scoop-mirror\n',
  'utf8',
)
const legacyHook = Buffer.from(
  '\n# >>> scoop-mirror-accel\n. "$env:SCOOP\\config\\mirror-accel.ps1"\n# <<< scoop-mirror-accel\n',
  'utf8',
)
const mixedLegacyThenCurrent = Buffer.concat([legacyHook, currentHook])
assert.equal(hasCurrentHookMarkers(currentHook), true)
assert.equal(hasCurrentHookMarkers(legacyHook), false)
assert.equal(hasCurrentHookMarkers(mixedLegacyThenCurrent), true)
assert.equal(hasCurrentHookMarkers(Buffer.from('no markers', 'utf8')), false)

const manageSource = read('scripts/windows/scoop/mirror/manage.ps1')
assert.match(manageSource, /Already active/)
assert.match(manageSource, /Enter on \*/)
assert.match(manageSource, /dashBase/)

const unknownSwitch = spawnSync(process.execPath, [filter, 'switch', 'not-a-real-mirror'], {
  env: { ...process.env, SCOOP: resolve(root, 'tmp-missing-scoop') },
  encoding: 'utf8',
})
assert.notEqual(unknownSwitch.status, 0)
assert.match(String(unknownSwitch.stderr || ''), /SCOOP environment variable is not set|Scoop mirror config not found/)

for (const profile of [
  'configs/windows/pwsh5_profile.ps1',
  'configs/windows/pwsh7_profile.ps1',
]) {
  const content = read(profile)
  assert.match(content, /config\\scoop\.ps1/)
  assert.match(content, /\. \$__scoopExt/)
}

const scoopPs = read('configs/windows/scoop/scoop.ps1')
assert.match(scoopPs, /['"]mirror['"]/)
assert.match(scoopPs, /cli\.mjs/)
assert.match(scoopPs, /switch/)
assert.match(scoopPs, /manage\.ps1/)
assert.match(scoopPs, /-MirrorChoice/)
assert.match(scoopPs, /scoop-mirror/)
assert.match(scoopPs, /scoop-services\\manage\.ps1/)
assert.match(scoopPs, /['"]services['"]/)
assert.match(scoopPs, /refusing uninstall without service cleanup/)
assert.match(scoopPs, /SCOOP_SHELL_INPROCESS/)
assert.match(scoopPs, /_scoop_invoke_helper/)
assert.match(scoopPs, /_scoop_prepare_update_services/)
assert.match(scoopPs, /_scoop_restart_changed_services/)
assert.match(scoopPs, /Test-ScoopHasManagedServices/)
assert.match(scoopPs, /\*\\\*-winsw-service\.xml/)
assert.ok(!scoopPs.includes("-Filter '*-winsw-service.xml' -Recurse"))
assert.match(scoopPs, /\.update-snapshot\.json/)
assert.match(scoopPs, /-PrepareUpdate/)
assert.match(scoopPs, /-RestartChanged/)
assert.match(scoopPs, /Node repair owns fast-path/)
assert.ok(!/powershell\.exe/.test(scoopPs))

const scoopZsh = read('configs/windows/scoop/scoop.zsh')
assert.match(scoopZsh, /['"]mirror['"]/)
assert.match(scoopZsh, /cli\.mjs/)
assert.match(scoopZsh, /switch/)
assert.match(scoopZsh, /manage\.ps1/)
assert.match(scoopZsh, /-MirrorChoice/)
assert.match(scoopZsh, /scoop-mirror/)
assert.match(scoopZsh, /scoop-services\/manage\.ps1/)
assert.match(scoopZsh, /['"]services['"]/)
assert.match(scoopZsh, /refusing uninstall without service cleanup/)
assert.match(scoopZsh, /PrepareUninstall/)
assert.match(scoopZsh, /PrepareUpdate/)
assert.match(scoopZsh, /RestartChanged/)
assert.match(scoopZsh, /_scoop_prepare_update_services/)
assert.match(scoopZsh, /_scoop_restart_changed_services/)
assert.match(scoopZsh, /_scoop_has_managed_services/)
assert.match(scoopZsh, /\.update-snapshot\.json/)
assert.match(scoopZsh, /_scoop_ps\(\)/)
assert.match(scoopZsh, /pwsh\.exe/)
assert.match(scoopZsh, /Node repair owns fast-path/)

const servicesHelper = read('scripts/windows/scoop/services/manage.ps1')
assert.match(servicesHelper, /\[switch\]\$PrepareUninstall/)
assert.match(servicesHelper, /\[switch\]\$PrepareUpdate/)
assert.match(servicesHelper, /\[switch\]\$RestartChanged/)
assert.match(servicesHelper, /Invoke-ScoopServicesManager/)
assert.match(servicesHelper, /Invoke-ScoopServicesPrepareUninstall/)
assert.match(servicesHelper, /Invoke-ScoopServicesPrepareUpdate/)
assert.match(servicesHelper, /Invoke-ScoopServicesRestartChanged/)
assert.match(servicesHelper, /scoop-services\\manifest\.json/)
assert.match(servicesHelper, /\.update-snapshot\.json/)
assert.match(servicesHelper, /restartOnUpdate/)
assert.match(servicesHelper, /Restarting service/)
assert.match(servicesHelper, /WarnIfMissing/)
assert.match(servicesHelper, /Get-ScoopServicesManifest -WarnIfMissing/)

const importBackup = read('scripts/windows/scoop/import-backup.ps1')
assert.match(importBackup, /New-ScoopMirroredImportFile/)
assert.match(importBackup, /Get-ScoopMirrorActivePrefix/)
assert.match(importBackup, /scoop import/)

assert.match(installer, /function New-ScoopMirroredImportFile/)
assert.match(installer, /ConvertTo-MirrorUrl/)
assert.match(installer, /\$bucket\.Source = \$mirrored/)
assert.match(installer, /GithubHosts/)
assert.match(installer, /Get-ScoopAccelConfig/)
assert.match(installer, /\$GithubHosts -contains \$hostName/)
assert.ok(!/raw\.githubusercontent\.com/.test(installer.match(/function ConvertTo-MirrorUrl[\s\S]*?\n}/)?.[0] || ''))

const rootDispatch = read('scripts/_dispatch.mjs')
assert.match(rootDispatch, /scoop-import/)
assert.ok(!/spawnSync\('scoop',\s*\[\s*'import'/.test(rootDispatch))

const menuSelect = read('scripts/lib/menu-select.mjs')
assert.match(menuSelect, /escape/)
assert.match(menuSelect, /CANCELLED/)
assert.match(menuSelect, /process\.exit\(130\)/)

const windowsManifest = JSON.parse(read('scripts/windows/_manifest.json'))
const syncLocals = windowsManifest.sync.toRepo.map((item) => item.local)
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/hook.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/shared.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/manage.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/cli.mjs')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/lib/menu-select.mjs')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/lib/tty-term.mjs')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-services/manage.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-services/manifest.json')))
assert.ok(syncLocals.some((local) => String(local).includes('config/scoop.ps1') || String(local).endsWith('/scoop.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop.zsh') || String(local).endsWith('/scoop.zsh')))
assert.equal(windowsManifest.scoopBackup, 'configs/windows/scoop/backup.json')
assert.equal(windowsManifest.scoopBackupLite, 'configs/windows/scoop/backup.lite.json')

const readme = read('README.md')
const mirrorSection = readme.match(/### scoop mirror\n([\s\S]*?)\n### scoop services/)
assert.ok(mirrorSection)
for (const command of [
  'scoop mirror',
  'scoop mirror status',
  'scoop mirror ghfast',
  'scoop mirror ghproxy',
  'scoop mirror official',
]) {
  assert.ok(mirrorSection[1].includes(command))
}
assert.ok(!mirrorSection[1].includes('scoop mirror list'))

assert.match(cliSource, /choice === 'status'/)
assert.match(cliSource, /printMirrorStatus\(config\)/)
assert.match(cliSource, /status\s+show active mirror/)
assert.match(manageSource, /\$Choice -eq 'status'/)
assert.match(manageSource, /Write-ScoopMirrorStatus/)
assert.match(scoopPs, /official\|status/)
assert.match(scoopZsh, /official\|status/)

const servicesSection = readme.match(/### scoop services\n([\s\S]*?)\n### clink/)
assert.ok(servicesSection)
assert.ok(servicesSection[1].includes('scoop update nginx'))
assert.ok(servicesSection[1].includes('restartOnUpdate'))
assert.ok(servicesSection[1].includes(':changed'))

console.log('scoop/mirror/test.mjs: ok')
