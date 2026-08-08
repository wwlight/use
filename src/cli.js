import { error } from "./core/log.js";
import { markCliInteractive, requirePlatform, stripArgSeparator } from "./core/platform.js";
import { runBackupCommand } from "./commands/backup.js";
import { runGitSetupCommand } from "./commands/git-setup.js";
import { runInitCommand } from "./commands/init.js";
import { runSetupCommand } from "./commands/setup.js";
import { runSyncCommand } from "./commands/sync.js";
import { runClinkCommand, runGitExtrasCommand, runZshInstallCommand } from "./commands/windows-extras.js";
import { runZshPluginCommand } from "./commands/zsh-plugin.js";
import { runBrewPmCommand } from "./pm/brew.js";
import { runScoopPmCommand } from "./pm/scoop.js";
const CROSS_PLATFORM = ['pm', 'init', 'backup', 'setup', 'sync', 'zsh-plugin', 'git-setup'];
const WIN_ONLY = ['zsh', 'git-extras', 'clink'];
const ALL = [...CROSS_PLATFORM, ...WIN_ONLY];
async function runTask(task, args) {
    const platform = requirePlatform();
    if (WIN_ONLY.includes(task) && platform !== 'windows') {
        error(`${task} supports Windows only`);
        return 1;
    }
    switch (task) {
        case 'pm':
            markCliInteractive();
            if (platform === 'macos')
                return runBrewPmCommand(args);
            return runScoopPmCommand(args);
        case 'init':
            return runInitCommand(platform, args);
        case 'backup':
            return runBackupCommand(platform);
        case 'setup':
            return runSetupCommand(platform, args);
        case 'sync':
            return runSyncCommand(platform, args);
        case 'zsh-plugin':
            return runZshPluginCommand(args);
        case 'git-setup':
            return runGitSetupCommand(args);
        case 'zsh':
            return runZshInstallCommand(args);
        case 'git-extras':
            return runGitExtrasCommand(args);
        case 'clink':
            return runClinkCommand(args);
        default:
            return 1;
    }
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
