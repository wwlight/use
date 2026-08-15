import { step, success } from "../core/log.js";
import { loadManifest, zshPluginsDir } from "../core/manifest.js";
import { expandPath, ensureDir, homeDir } from "../core/paths.js";
import { syncGitRepoPlugin } from "../core/git.js";
import { stripArgSeparator } from "../core/platform.js";

/** Resolve whether plugins should be updated (standalone default: yes). */
export function resolveZshPluginUpdate(args = [], options = {}) {
    const clean = stripArgSeparator(args);
    let update = options.update ?? true;
    for (const arg of clean) {
        if (arg === '--update')
            update = true;
        else if (arg === '--no-update')
            update = false;
        else
            throw new Error(`Unknown argument: ${arg} (supported: --update, --no-update)`);
    }
    return update;
}

export async function runZshPluginCommand(args = [], options = {}) {
    const update = resolveZshPluginUpdate(args, options);
    if (options.header !== false) {
        step(update ? 'Installing/updating Zsh plugins...' : 'Installing Zsh plugins...');
    }
    const plugins = loadManifest('common').zshPlugins ?? [];
    const dir = expandPath(zshPluginsDir(), { home: homeDir() });
    ensureDir(dir);
    let made = 0;
    for (const plugin of plugins) {
        const status = await syncGitRepoPlugin(plugin.repo, `${dir}/${plugin.name}`, plugin.name, update);
        if (status !== 'skipped')
            made++;
    }
    const total = plugins.length;
    const skipped = total - made;
    if (made === 0) {
        success(update
            ? `All ${total} Zsh plugins already up to date`
            : `All ${total} Zsh plugins already installed; skipped`);
    }
    else if (skipped === 0) {
        success(update ? `Updated ${made} Zsh plugins` : `Installed ${made} Zsh plugins`);
    }
    else {
        success(update
            ? `Updated ${made} and skipped ${skipped} Zsh plugins`
            : `Installed ${made} and skipped ${skipped} Zsh plugins`);
    }
    return 0;
}
