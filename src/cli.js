import { error } from "./core/log.js";
import { markCliInteractive, requirePlatform, stripArgSeparator } from "./core/platform.js";
import { runBackupCommand } from "./commands/backup.js";
import { runGitSetupCommand } from "./commands/git-setup.js";
import { runInitCommand } from "./commands/init.js";
import { runSetupCommand } from "./commands/setup.js";
import { runSyncCommand } from "./commands/sync.js";
import { runClinkCommand, runGitExtrasCommand, runZshInstallCommand } from "./commands/windows-extras.js";
import { runGenerateCommand } from "./commands/generate.js";
import { runZshPluginCommand } from "./commands/zsh-plugin.js";
import { runBrewPmCommand } from "./pm/brew.js";
import { runScoopPmCommand } from "./pm/scoop.js";
const COMMANDS = {
    'pm': {
        platforms: ['macos', 'windows'],
        run: async (platform, args) => {
            markCliInteractive();
            return platform === 'macos' ? runBrewPmCommand(args) : runScoopPmCommand(args);
        },
    },
    'init': { platforms: ['macos', 'windows'], run: (platform, args) => runInitCommand(platform, args) },
    'backup': { platforms: ['macos', 'windows'], run: (platform) => runBackupCommand(platform) },
    'setup': { platforms: ['macos', 'windows'], run: (platform, args) => runSetupCommand(platform, args) },
    'sync': { platforms: ['macos', 'windows'], run: (platform, args) => runSyncCommand(platform, args) },
    'zsh-plugin': { platforms: ['macos', 'windows'], run: (_platform, args) => runZshPluginCommand(args) },
    'generate': { platforms: ['macos', 'windows'], run: (_platform, args) => runGenerateCommand(args) },
    'git-setup': { platforms: ['macos', 'windows'], run: (_platform, args) => runGitSetupCommand(args) },
    'zsh': { platforms: ['windows'], run: (_platform, args) => runZshInstallCommand(args) },
    'git-extras': { platforms: ['windows'], run: (_platform, args) => runGitExtrasCommand(args) },
    'clink': { platforms: ['windows'], run: (_platform, args) => runClinkCommand(args) },
};
const ALL = Object.keys(COMMANDS);
async function runTask(task, args) {
    const platform = requirePlatform();
    const cmd = COMMANDS[task];
    if (!cmd.platforms.includes(platform)) {
        error(`${task} supports ${cmd.platforms.join(' / ')} only`);
        return 1;
    }
    return cmd.run(platform, args);
}
async function main() {
    // Strip every "--" first. Windows PowerShell 5.1 may insert/shift a bare "--"
    // (especially via node.ps1 shims) so argv[2] is not the real task.
    const tokens = stripArgSeparator(process.argv.slice(2));
    const task = tokens[0];
    const args = tokens.slice(1);
    if (!task || !ALL.includes(task)) {
        console.error(`Usage: node src/cli.js <${ALL.join('|')}> [args...]`);
        process.exit(1);
    }
    try {
        process.exit(await runTask(task, args));
    }
    catch (err) {
        error(err.message);
        process.exit(1);
    }
}
await main();
