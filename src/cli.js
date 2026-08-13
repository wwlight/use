import { error, handleFatalError } from "./core/log.js";
import { markCliInteractive, requirePlatform, stripArgSeparator } from "./core/platform.js";
import { runBackupCommand } from "./commands/backup.js";
import { runGitSetupCommand } from "./commands/git-setup.js";
import { runInitCommand } from "./commands/init.js";
import { runSetupCommand } from "./commands/setup.js";
import { runSyncCommand } from "./commands/sync.js";
import { runClinkCommand, runGitExtrasCommand, runZshInstallCommand } from "./commands/windows-extras.js";
import { runGenerateCommand } from "./commands/generate.js";
import { runZshPluginCommand } from "./commands/zsh-plugin.js";
import { runRepoUpdateCommand } from "./commands/repo-update.js";
import { runBrewPmCommand } from "./pm/brew/index.js";
import { runScoopPmCommand } from "./pm/scoop/index.js";
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
    'repo-update': { platforms: ['macos', 'windows'], run: (_platform, args) => runRepoUpdateCommand(args[0]) },
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
    // Guard against spinner/menu residue leaking into the shell after an abrupt
    // exit (Ctrl+C while a \r spinner is mid-frame would leave its text on the
    // prompt line, where the shell can re-execute it as a command).
    for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143]]) {
        process.on(signal, () => {
            process.stderr.write('\n');
            process.exit(code);
        });
    }
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
        handleFatalError(err);
        process.exit(1);
    }
}
await main();
