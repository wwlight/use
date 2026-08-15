#!/usr/bin/env node
/**
 * Pure Scoop mirror URL helpers shared by src/pm/scoop and the deployed
 * mirror/cli.js (deployed to ~/.config/scoop/mirror/lib/).
 * Deployed copy must stay free of src/ imports; this file is dependency-free.
 */

export function normalizePrefix(prefix) {
    const value = String(prefix || '').trim();
    if (!value)
        return '';
    return value.endsWith('/') ? value : `${value}/`;
}

/** Normalized prefix list from a mirrors array ({ id, prefix }). */
export function mirrorPrefixes(mirrors) {
    const prefixes = [];
    for (const item of mirrors || []) {
        const p = normalizePrefix(item?.prefix);
        if (p && !prefixes.includes(p))
            prefixes.push(p);
    }
    return prefixes;
}

/** Strip the first matching mirror prefix (case-insensitive). */
export function stripMirrorPrefix(url, prefixes) {
    for (const prefix of prefixes) {
        const known = normalizePrefix(prefix);
        if (known && url.toLowerCase().startsWith(known.toLowerCase())) {
            return url.slice(known.length);
        }
    }
    return url;
}

/** True when the URL's hostname is in the github-host allowlist. */
export function isGithubHost(url, hosts) {
    try {
        return hosts.includes(new URL(url).hostname);
    }
    catch {
        return false;
    }
}

/** Strip any known prefix, then rejoin with the active prefix (empty = official). */
export function joinScoopMirrorUrl(url, prefix, allPrefixes = []) {
    if (!url)
        return url;
    let bare = String(url).trim();
    for (const p of allPrefixes) {
        const known = normalizePrefix(p);
        if (known && bare.toLowerCase().startsWith(known.toLowerCase())) {
            bare = bare.slice(known.length);
            break;
        }
    }
    const active = normalizePrefix(prefix);
    if (!active)
        return bare;
    return active + bare;
}

/** Rewrite a GitHub URL through the active mirror; non-GitHub URLs stay bare. */
export function convertToMirrorUrl(url, prefix, allPrefixes, githubHosts) {
    if (!url)
        return url;
    let bare = String(url).trim();
    for (const p of allPrefixes) {
        const known = normalizePrefix(p);
        if (known && bare.toLowerCase().startsWith(known.toLowerCase())) {
            bare = bare.slice(known.length);
            break;
        }
    }
    if (!isGithubHost(bare, githubHosts || []))
        return bare;
    return joinScoopMirrorUrl(bare, prefix, allPrefixes);
}

/** Resolve a config mirror-list's prefix back to its id; empty prefix → official. */
export function mirrorId(prefix, mirrors) {
    if (!prefix)
        return 'official';
    for (const mirror of mirrors) {
        if (mirror.prefix === prefix || mirror.prefix.replace(/\/$/, '') === prefix.replace(/\/$/, '')) {
            return mirror.id;
        }
    }
    return prefix;
}

/** Resolve a mirror choice (id/prefix/official) to an active prefix. */
export function resolveMirrorChoice(choice, mirrors) {
    const value = String(choice || '').trim();
    if (value === 'official')
        return '';
    for (const mirror of mirrors) {
        if (mirror.id === value
            || mirror.prefix === value
            || mirror.prefix.replace(/\/$/, '') === value.replace(/\/$/, '')) {
            return mirror.prefix;
        }
    }
    throw new Error(`Unknown Scoop mirror '${choice}'. Run 'scoop mirror' to see available mirrors.`);
}
