/**
 * tealdeer (tldr) archive_source sync for Scoop mirrors (~/.config/scoop/mirror/tealdeer.js).
 *
 * Writes the active GitHub-accel prefix into tealdeer's [updates].archive_source so
 * `tldr --update` fetches pages through the same mirror Scoop uses. Pins download_languages
 * to en + zh (smaller per-language archives instead of the full tldr.zip) and disables
 * auto_update so typing `tldr <cmd>` never triggers a download. No-op when tealdeer is
 * not installed (no config file found).
 *
 * Config resolution order (first file that exists wins):
 *   1. $SCOOP/persist/tealdeer/config.toml   (Scoop persist; hard-linked to current/)
 *   2. $TEALDEER_CONFIG_DIR/config.toml      (explicit tealdeer override)
 *   3. $XDG_CONFIG_HOME/tealdeer/config.toml or ~/.config/tealdeer/config.toml
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const TLDR_ARCHIVE_URL = 'https://github.com/tldr-pages/tldr/releases/latest/download/'
export const TLDR_UPDATES_AUTO = false
export const TLDR_DOWNLOAD_LANGUAGES = ['en', 'zh']

/** Normalize a URL so it ends with exactly one trailing '/'. */
function withTrailingSlash(value) {
    const s = String(value || '').trim()
    return s ? (s.endsWith('/') ? s : `${s}/`) : ''
}

export function buildTldrArchiveSource(activePrefix) {
    const prefix = withTrailingSlash(activePrefix)
    return prefix ? prefix + TLDR_ARCHIVE_URL : TLDR_ARCHIVE_URL
}

function configDirCandidates(env = process.env) {
    const home = env.USERPROFILE || env.HOME || os.homedir()
    const dirs = []
    if (env.SCOOP?.trim())
        dirs.push(path.join(env.SCOOP.trim(), 'persist', 'tealdeer'))
    if (env.TEALDEER_CONFIG_DIR?.trim())
        dirs.push(path.join(env.TEALDEER_CONFIG_DIR.trim()))
    const xdg = env.XDG_CONFIG_HOME?.trim()
    if (xdg)
        dirs.push(path.join(xdg, 'tealdeer'))
    dirs.push(path.join(home, '.config', 'tealdeer'))
    return dirs
}

export function resolveTldrConfigPath(env = process.env) {
    for (const dir of configDirCandidates(env)) {
        const file = path.join(dir, 'config.toml')
        if (fs.existsSync(file))
            return file
    }
    return null
}

/**
 * Update [updates].archive_source (and auto_update) in a small TOML config while
 * preserving every other section/key. Returns the new file content.
 */
export function renderTldrConfig(content, archiveSource, downloadLanguages = TLDR_DOWNLOAD_LANGUAGES) {
    const lines = String(content || '').split(/\r?\n/)
    const out = []
    let section = ''
    let updatesIndex = -1
    let sourceReplaced = false
    let autoReplaced = false
    let langReplaced = false

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i]
        const header = line.match(/^\s*\[([^\]]+)\]\s*$/)
        if (header) {
            section = header[1].trim().toLowerCase()
            out.push(line)
            if (section === 'updates' && updatesIndex < 0)
                updatesIndex = out.length
            continue
        }
        const keyMatch = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=\s*/)
        if (keyMatch && section === 'updates') {
            const key = keyMatch[1]
            if (key === 'archive_source') {
                out.push(`archive_source = "${archiveSource}"`)
                sourceReplaced = true
                continue
            }
            if (key === 'auto_update') {
                out.push(`auto_update = ${TLDR_UPDATES_AUTO}`)
                autoReplaced = true
                continue
            }
            if (key === 'download_languages') {
                out.push(`download_languages = ${renderLanguageList(downloadLanguages)}`)
                langReplaced = true
                continue
            }
        }
        out.push(line)
    }

    if (updatesIndex < 0) {
        out.push('', '[updates]')
        updatesIndex = out.length
    }
    const insert = []
    if (!sourceReplaced)
        insert.push(`archive_source = "${archiveSource}"`)
    if (!autoReplaced)
        insert.push(`auto_update = ${TLDR_UPDATES_AUTO}`)
    if (!langReplaced && downloadLanguages.length > 0)
        insert.push(`download_languages = ${renderLanguageList(downloadLanguages)}`)
    if (insert.length > 0)
        out.splice(updatesIndex, 0, ...insert)
    return out.join('\n').replace(/\n+$/, '\n')
}

function renderLanguageList(languages) {
    return `[${languages.map((l) => `"${l}"`).join(', ')}]`
}

/**
 * Rewrite tealdeer's config to follow the active Scoop mirror.
 * @returns {{ applied: boolean, configPath: string|null, archiveSource: string|null, skipped: string|null }}
 */
export function applyTldrMirror(activePrefix, env = process.env) {
    const configPath = resolveTldrConfigPath(env)
    if (!configPath) {
        return { applied: false, configPath: null, archiveSource: null, skipped: 'tealdeer config not found (not installed?)' }
    }
    const archiveSource = buildTldrArchiveSource(activePrefix)
    const current = fs.readFileSync(configPath, 'utf8')
    const next = renderTldrConfig(current, archiveSource)
    if (next !== current)
        fs.writeFileSync(configPath, next, 'utf8')
    return { applied: true, configPath, archiveSource, skipped: null }
}
