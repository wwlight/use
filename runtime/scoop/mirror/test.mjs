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

const installer = read('runtime/scoop/accel.ps1')
assert.match(installer, /Join-Path \$PSScriptRoot 'deploy\.ps1'/)
assert.match(installer, /Join-Path \$Script:ProjectRoot 'src\\lib\\menu-select\.js'/)
assert.ok(!/PSScriptRoot '..\\..\\src\\lib\\menu-select/.test(installer))
assert.match(installer, /Invoke-ScoopMirrorAccelFilterInit/)
assert.match(installer, /Install-ScoopMirrorAccelFiles/)
assert.match(installer, /Install-ScoopServicesFiles/)
assert.match(installer, /scoop-mirror\\cli\.js/)
assert.match(installer, /\$cliJs repair/)
assert.ok(!installer.includes('Fallback without Node'))
assert.ok(!installer.includes('Initialize-ScoopMirrorAccelFilter'))

const deploy = read('runtime/scoop/deploy.ps1')
assert.match(deploy, /mirrors\s*=\s*\$mirrors/)
assert.match(deploy, /scoopRepo\s*=\s*\[string\]\$Accel\.scoopRepo/)
assert.match(deploy, /scoop-mirror/)
assert.match(deploy, /config\\scoop-mirror/)
assert.match(deploy, /scoop\/mirror\/hook\.ps1|mirror\\hook\.ps1/)
assert.match(deploy, /shared\.ps1/)
assert.match(deploy, /obsoleteManage/)
assert.match(deploy, /Remove-Item/)
assert.ok(!deploy.includes("foreach ($name in @('shared.ps1', 'manage.ps1'))"))
assert.match(deploy, /scoop\/services\/manage\.ps1|services\\manage\.ps1/)
assert.match(deploy, /scoop\/mirror\/shared\.ps1|mirror\\shared\.ps1/)
assert.match(deploy, /configs\\windows\\scoop\\scoop\.ps1/)
assert.ok(!/hooks[\\/]windows[\\/]scoop/.test(deploy))
assert.match(deploy, /Join-Path \$Script:ProjectRoot 'src\\lib'/)
assert.ok(!/PSScriptRoot '..\\..\\src\\lib'/.test(deploy))

const hook = read('runtime/scoop/mirror/hook.ps1')
assert.match(hook, /shared\.ps1/)
assert.match(hook, /Start-Download/)
assert.match(hook, /Invoke-CachedAria2Download/)
assert.match(hook, /configured GitHub mirrors cannot proxy/)
assert.ok(!/\$cliJs repair|node.*cli\.js.*repair|RepairHook|PrepareCommand/.test(hook))
assert.ok(!/Invoke-ScoopMirrorManager/.test(hook))
assert.ok(!/\[switch\]\$ManageMirror/.test(hook))
assert.ok(!/\[switch\]\$GitFilterClean/.test(hook))
assert.ok(!/function Find-ByteSequence/.test(hook))
assert.ok(!/function Initialize-ScoopMirrorAccelFilter/.test(hook))
assert.ok(!/Fallback when Node is unavailable/.test(hook))

const shared = read('runtime/scoop/mirror/shared.ps1')
assert.match(shared, /function Get-ScoopMirrorAccelConfig/)
assert.match(shared, /function Get-ScoopMirrorAccelCandidates/)
assert.match(shared, /function ConvertTo-ScoopMirrorUrl/)
assert.match(shared, /Scoop source: cache/)
assert.match(shared, /return 'direct'/)
assert.match(shared, /GitHub mirror unavailable for this host/)
assert.ok(!/function Set-ScoopMirrorBucketRemotes/.test(shared))
assert.ok(!/function Write-ScoopMirrorStatus/.test(shared))
assert.ok(!/function Resolve-ScoopMirrorAccelChoice/.test(shared))

assert.ok(!existsSync(resolve(root, 'runtime/scoop/mirror/manage.ps1')))

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
const legacy = Buffer.concat([
  tracked,
  Buffer.from('\n# >>> scoop-mirror-accel\n. "$env:SCOOP\\config\\mirror-accel.ps1"\n# <<< scoop-mirror-accel\n', 'utf8'),
])
assert.deepEqual(runFilter('clean', legacy), tracked)

const cliSource = read('runtime/scoop/mirror/cli.js')
assert.match(cliSource, /manifests['"`].*common\.json|common\.json/)
assert.match(cliSource, /src['"`].*lib['"`].*menu-select|src.*lib.*menu-select/)
assert.ok(!cliSource.includes("../../../src/lib/menu-select.js"))
assert.ok(existsSync(resolve(root, 'src/lib/menu-select.js')))
assert.match(cliSource, /mode === 'switch'/)
assert.match(cliSource, /runSwitchCli/)
assert.match(cliSource, /Canceled/)
assert.match(cliSource, /console\.error\('Canceled'\)/)
assert.match(cliSource, /process\.exit\(130\)/)
assert.match(cliSource, /Already active/)
assert.match(cliSource, /Enter on \*/)
assert.match(cliSource, /scoop_repo/)
assert.match(cliSource, /activePrefix/)
assert.match(cliSource, /formatAlignedChoices/)
assert.match(cliSource, /function isRepairHealthy/)
assert.match(cliSource, /if \(isRepairHealthy\(/)
assert.match(cliSource, /hasCurrentHookMarkers/)
assert.match(cliSource, /Reject legacy/)
assert.match(cliSource, /choice === 'status'/)
assert.match(cliSource, /printMirrorStatus\(config\)/)
assert.match(cliSource, /status\s+show active mirror/)

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
assert.match(scoopPs, /cli\.js/)
assert.match(scoopPs, /switch/)
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
assert.match(scoopPs, /Node\.js is required/)
assert.match(scoopPs, /_scoop_run_mirror_repair/)
assert.match(scoopPs, /_scoop_mirror_cli/)
assert.ok(!/scoop-mirror\\manage\.ps1/.test(scoopPs))
assert.ok(!/-MirrorChoice/.test(scoopPs))
assert.ok(!/powershell\.exe/.test(scoopPs))
assert.match(scoopPs, /official\|status/)

const scoopZsh = read('configs/windows/scoop/scoop.zsh')
assert.match(scoopZsh, /['"]mirror['"]/)
assert.match(scoopZsh, /cli\.js/)
assert.match(scoopZsh, /switch/)
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
assert.match(scoopZsh, /Node\.js is required/)
assert.match(scoopZsh, /_scoop_run_mirror_repair/)
assert.match(scoopZsh, /_scoop_mirror_cli/)
assert.ok(!/-MirrorChoice/.test(scoopZsh))
assert.match(scoopZsh, /official\|status/)

const servicesHelper = read('runtime/scoop/services/manage.ps1')
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

const importBackup = read('runtime/scoop/import-backup.ps1')
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

// Interactive `vpr pm` must prompt even when USE_ACCEL is leftover from a one-liner.
const resolveMirror = installer.match(/function Resolve-ScoopMirrorSelection[\s\S]*?\nfunction /)?.[0] || ''
assert.match(resolveMirror, /USE_ACCEL/)
assert.match(resolveMirror, /Test-InteractivePrompt/)
assert.match(resolveMirror, /MENU_SELECT_INITIAL|InitialValue/)
assert.ok(
  /if\s*\([^)]*USE_ACCEL[\s\S]*?-not\s*\(Test-InteractivePrompt\)/.test(resolveMirror)
  || /hintFromEnv[\s\S]*?-not\s*\(Test-InteractivePrompt\)[\s\S]*\$Choice\s*=\s*\$hintFromEnv/.test(resolveMirror),
  'USE_ACCEL must only auto-select when non-interactive',
)
assert.match(installer, /\$env:MENU_SELECT_INITIAL/)

const rootInstall = read('install.ps1')
assert.match(rootInstall, /Invoke-UseCli|src\/cli\.js/)
assert.match(rootInstall, /USE_ACCEL/)
assert.match(rootInstall, /\$scoopInstallArgs|Fetch-UseRepository|Expand-UseZipRepository/)
assert.match(rootInstall, /Unblock-UseScripts|Unblock-File/)
assert.match(rootInstall, /Ensure-NodeRuntime/)

// Bootstrap Scoop via selected mirror (preferred → other mirrors → upstream).
const bootstrap = installer.match(/function Invoke-ScoopInstallScriptWithFallback[\s\S]*?\nfunction /)?.[0] || ''
assert.match(bootstrap, /Get-ScoopMirrorFetchAttempts/)
assert.match(bootstrap, /Rewrite-ScoopInstallerGithubUrls/)
assert.match(bootstrap, /Trying installer/)
assert.match(bootstrap, /Installer succeeded/)
assert.match(bootstrap, /Installer failed/)
assert.match(bootstrap, /active mirror set to/)
assert.match(bootstrap, /return \$successPrefix/)
assert.ok(!/\$null\s*=\s*\$PreferredPrefix/.test(bootstrap), 'must not discard PreferredPrefix')
assert.ok(!/Mirror acceleration starts after Scoop installs/.test(bootstrap))

const rewrite = installer.match(/function Rewrite-ScoopInstallerGithubUrls[\s\S]*?\nfunction /)?.[0] || ''
assert.match(rewrite, /Get-ScoopInstallerBootstrapUrls|ScoopInstaller\/Scoop\/archive\/master\.zip/)
assert.match(rewrite, /ScoopInstaller\/Scoop\.git|Get-ScoopInstallerBootstrapUrls/)
assert.match(rewrite, /refusing to run against upstream GitHub|were not rewritten/)
assert.match(rewrite, /produced no mirrored Scoop\/Main URLs|mirroredHit/)

const bootstrapUrls = installer.match(/function Get-ScoopInstallerBootstrapUrls[\s\S]*?\nfunction /)?.[0] || ''
assert.match(bootstrapUrls, /ScoopInstaller\/Scoop\/archive\/master\.zip/)
assert.match(bootstrapUrls, /ScoopInstaller\/Main\/archive\/master\.zip/)
assert.match(bootstrapUrls, /ScoopInstaller\/Scoop\.git/)
assert.match(bootstrapUrls, /ScoopInstaller\/Main\.git/)

const fetchAttempts = installer.match(/function Get-ScoopMirrorFetchAttempts[\s\S]*?\nfunction /)?.[0] || ''
assert.match(fetchAttempts, /PreferredPrefix/)
assert.match(fetchAttempts, /official: do not probe mirrors first|do not probe mirrors first/)

const scoopInstall = read('runtime/scoop/install.ps1')
assert.match(scoopInstall, /\$selectedPrefix = Resolve-ScoopMirrorSelection/)
assert.match(scoopInstall, /\$activePrefix = Invoke-ScoopInstallScriptWithFallback/)
assert.match(scoopInstall, /after install fallback/)

const cliTs = read('src/cli.js')
assert.match(cliTs, /runtime\/scoop\/install\.ps1/)
assert.match(cliTs, /markCliInteractive/)
assert.match(cliTs, /runInitCommand/)
assert.ok(!/process\.stdin\.isTTY \|\| process\.stdout\.isTTY/.test(cliTs))
assert.ok(!/windows\/scoop\//.test(cliTs))
assert.ok(!/macos\/brew\//.test(cliTs))
assert.ok(!/scripts\/scoop\//.test(cliTs))

const initTs = read('src/commands/init.js')
assert.match(initTs, /runtime\/scoop\/import-backup\.ps1/)
assert.match(initTs, /Scoop/)
assert.ok(!/windows\/scoop\//.test(initTs))
assert.ok(!/scripts\/scoop\//.test(initTs))

const pathsTs = read('src/core/paths.js')
assert.match(pathsTs, /expandPath|projectRoot/)

const manifestTs = read('src/core/manifest.js')
assert.match(manifestTs, /loadManifest|pathVarsForWindows/)

const utilsPs = read('runtime/scoop/utils.ps1')
assert.match(utilsPs, /Get-ExpandedPath|Read-Manifest/)
assert.ok(!utilsPs.includes('function Write-Step'))
assert.ok(!existsSync(resolve(root, 'scripts/lib/utils.ps1')))
assert.ok(!existsSync(resolve(root, 'scripts')))
assert.ok(existsSync(resolve(root, 'runtime/scoop/utils.ps1')))

const syncSelect = read('src/sync/select.js')
assert.match(syncSelect, /allowWindowsConsole:\s*true/)

const syncDirection = read('src/sync/direction.js')
assert.match(syncDirection, /MENU_SELECT_OUT/)

const menuSelect = read('src/lib/menu-select.js')
assert.match(menuSelect, /escape/)
assert.match(menuSelect, /CANCELLED/)
assert.match(menuSelect, /console\.error\('Canceled'\)/)
assert.match(menuSelect, /process\.exit\(130\)/)
assert.match(menuSelect, /formatAlignedChoices/)

const windowsManifest = JSON.parse(read('manifests/windows.json'))
const syncLocals = windowsManifest.sync.toRepo.map((item) => item.local)
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/hook.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/shared.ps1')))
assert.ok(!syncLocals.some((local) => String(local).includes('scoop-mirror/manage.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/cli.js')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/lib/menu-select.js')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/lib/string-width.js')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-mirror/lib/tty-term.js')))
assert.match(deploy, /string-width\.js/)
assert.match(menuSelect, /string-width\.js/)
assert.ok(syncLocals.some((local) => String(local).includes('scoop-services/manage.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop-services/manifest.json')))
assert.ok(syncLocals.some((local) => String(local).includes('config/scoop.ps1') || String(local).endsWith('/scoop.ps1')))
assert.ok(syncLocals.some((local) => String(local).includes('scoop.zsh') || String(local).endsWith('/scoop.zsh')))
assert.equal(windowsManifest.scoopBackup, 'configs/windows/scoop/backup.json')
assert.equal(windowsManifest.scoopBackupLite, 'configs/windows/scoop/backup.lite.json')

const readme = read('README.md')
const mirrorSection = readme.match(/### scoop mirror\n([\s\S]*?)\n### scoop services/)
assert.ok(mirrorSection)
assert.ok(!mirrorSection[1].includes('manage.ps1') || mirrorSection[1].includes('scoop-services'))
assert.ok(!/scoop-mirror\/manage\.ps1/.test(mirrorSection[1]))
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

const servicesSection = readme.match(/### scoop services\n([\s\S]*?)\n### clink/)
assert.ok(servicesSection)
assert.ok(servicesSection[1].includes('scoop update nginx'))
assert.ok(servicesSection[1].includes('restartOnUpdate'))
assert.ok(servicesSection[1].includes(':changed'))

console.log('scoop/mirror/test.mjs: ok')
