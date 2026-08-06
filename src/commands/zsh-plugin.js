import { info } from "../core/log.js";
import { loadManifest, zshPluginsDir } from "../core/manifest.js";
import { expandPath, ensureDir, homeDir } from "../core/paths.js";
import { syncGitRepoPlugin } from "../core/git.js";
import { stripArgSeparator } from "../core/platform.js";
export async function runZshPluginCommand(args = []) {
    const clean = stripArgSeparator(args);
    let update = false;
    for (const arg of clean) {
        if (arg === '--update')
            update = true;
        else
            throw new Error(`Unknown argument: ${arg} (supported: --update)`);
    }
    info('Installing Zsh plugins...');
    const plugins = loadManifest('common').zshPlugins ?? [];
    const dir = expandPath(zshPluginsDir(), { home: homeDir() });
    ensureDir(dir);
    for (const plugin of plugins) {
        syncGitRepoPlugin(plugin.repo, `${dir}/${plugin.name}`, plugin.name, update);
    }
    return 0;
}
