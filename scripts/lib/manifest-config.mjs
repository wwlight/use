#!/usr/bin/env node
/**
 * Manifest access and usage-text generation.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export function loadManifest(scope) {
  const manifestPath = path.join(__dirname, `../${scope}/_manifest.json`)
  return JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
}

export function hasProfile(name, common = loadManifest('common')) {
  return Boolean(common.profiles?.[name])
}

export function profileLabel(name, common = loadManifest('common')) {
  const label = common.profiles?.[name]?.label
  if (!label) throw new Error(`Unknown profile: ${name}`)
  return label
}

export function profileMenuItems(common = loadManifest('common')) {
  return Object.entries(common.profiles).map(([k, v]) => `${k}) ${v.label}`)
}

export function formatInitUsage(common = loadManifest('common')) {
  const keys = Object.keys(common.profiles)
  const pad = Math.max(...keys.map((k) => k.length))
  return [
    `Usage: vpr init [${keys.join('|')}]`,
    '',
    ...keys.map((k) => `  ${k.padEnd(pad)}  ${common.profiles[k].label}`),
    '',
    'Examples:',
    '  vpr init',
    ...keys.map((k) => `  vpr init -- ${k}`),
  ].join('\n')
}

export function hasMirror(name, macos = loadManifest('macos')) {
  return Boolean(macos.brewMirrors?.[name])
}

export function mirrorMenuItems(macos = loadManifest('macos')) {
  return Object.entries(macos.brewMirrors).map(([k, v]) => `${k}) ${v.label}`)
}

export function formatPmUsage(macos = loadManifest('macos')) {
  const keys = Object.keys(macos.brewMirrors)
  const pad = Math.max(...keys.map((k) => k.length))
  return [
    `Usage: vpr pm [${keys.join('|')}]`,
    '',
    ...keys.map((k) => `  ${k.padEnd(pad)}  ${macos.brewMirrors[k].label}`),
    '',
    'Examples:',
    '  vpr pm',
    ...keys.map((k) => `  vpr pm -- ${k}`),
  ].join('\n')
}

/** @returns {{ mode: 'git', url: string } | { mode: 'script', url: string }} */
export function mirrorInstallMode(cfg, officialScript) {
  if (cfg?.installGitRepo) return { mode: 'git', url: cfg.installGitRepo }
  const url = cfg?.installScript || officialScript
  if (!url) throw new Error('installScript / installGitRepo missing')
  return { mode: 'script', url }
}

export function resolveProfileArtifact(scope, profile) {
  const m = loadManifest(scope)
  const artifactKey = m.profileArtifacts?.[profile]
  if (!artifactKey) throw new Error(`${scope} is missing profileArtifacts.${profile}`)
  const rel = m[artifactKey]
  if (!rel) throw new Error(`${scope} is missing field: ${artifactKey}`)
  return rel
}

export function zshPluginsDir(common = loadManifest('common')) {
  if (!common.zshPluginsDir) throw new Error('common manifest is missing zshPluginsDir')
  return common.zshPluginsDir
}

function main(argv) {
  const [cmd, ...args] = argv
  switch (cmd) {
    case 'usage-init':
      process.stdout.write(`${formatInitUsage()}\n`)
      break
    case 'usage-pm':
      process.stdout.write(`${formatPmUsage()}\n`)
      break
    case 'has-profile':
      process.exit(hasProfile(args[0]) ? 0 : 1)
      break
    case 'profile-label':
      process.stdout.write(profileLabel(args[0]))
      break
    case 'menu-profiles':
      process.stdout.write(`${profileMenuItems().join('\n')}\n`)
      break
    case 'menu-mirrors':
      process.stdout.write(`${mirrorMenuItems().join('\n')}\n`)
      break
    case 'has-mirror':
      process.exit(hasMirror(args[0]) ? 0 : 1)
      break
    case 'profile-artifact':
      process.stdout.write(resolveProfileArtifact(args[0], args[1]))
      break
    case 'zsh-plugins-dir':
      process.stdout.write(zshPluginsDir())
      break
    case 'mirror-install': {
      const macos = loadManifest('macos')
      const cfg = macos.brewMirrors[args[0]] || {}
      const mode = mirrorInstallMode(cfg, macos.brewMirrors.official?.installScript)
      process.stdout.write(`${mode.mode}\t${mode.url}\n`)
      break
    }
    default:
      console.error(`Usage: manifest-config.mjs <usage-init|usage-pm|has-profile|profile-label|menu-profiles|menu-mirrors|has-mirror|profile-artifact|zsh-plugins-dir|mirror-install>`)
      process.exit(1)
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2))
}
