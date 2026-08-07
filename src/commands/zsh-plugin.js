import { info } from "../core/log.js";
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
    info(update ? 'Installing/updating Zsh plugins...' : 'Installing Zsh plugins...');
    const plugins = loadManifest('common').zshPlugins ?? [];
    const dir = expandPath(zshPluginsDir(), { home: homeDir() });
    ensureDir(dir);
    for (const plugin of plugins) {
        syncGitRepoPlugin(plugin.repo, `${dir}/${plugin.name}`, plugin.name, update);
    }
    return 0;
}
