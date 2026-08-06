import { spawnSync } from 'node:child_process';
import readline from 'node:readline';
import { info, warn } from "../core/log.js";
import { loadManifest } from "../core/manifest.js";
import { markCliInteractive } from "../core/platform.js";
function gitAvailable() {
    return spawnSync('git', ['--version'], { stdio: 'ignore' }).status === 0;
}
function gitConfig(args) {
    spawnSync('git', ['config', '--global', ...args], { stdio: 'inherit' });
}
function hasGitIdentity() {
    const name = spawnSync('git', ['config', '--global', '--get', 'user.name'], { stdio: 'ignore' });
    const email = spawnSync('git', ['config', '--global', '--get', 'user.email'], { stdio: 'ignore' });
    return name.status === 0 && email.status === 0;
}
async function readTty(prompt) {
    if (!process.stdin.isTTY)
        return null;
    const rl = readline.createInterface({ input: process.stdin, output: process.stderr });
    try {
        return await new Promise((resolve) => {
            rl.question(prompt, (answer) => resolve(answer));
        });
    }
    finally {
        rl.close();
    }
}
export async function runGitSetupCommand(_args = []) {
    markCliInteractive();
    if (!gitAvailable()) {
        warn('Git is not installed; skipping Git configuration');
        return 0;
    }
    const git = loadManifest('common').git ?? {};
    gitConfig(['init.defaultBranch', String(git.defaultBranch ?? 'main')]);
    gitConfig(['core.ignorecase', String(git.ignorecase ?? false)]);
    spawnSync('git', ['config', '--global', '--replace-all', 'safe.directory', String(git.safeDirectory ?? '*')], { stdio: 'inherit' });
    gitConfig(['credential.helper', String(git.credentialHelper ?? 'store')]);
    if (hasGitIdentity()) {
        info('Git username and email are already configured; skipping');
        return 0;
    }
    const skip = await readTty('Skip Git username and email configuration? (y/n) [default: n]: ');
    if (skip === null) {
        info('Non-interactive environment; skipping Git username and email configuration');
        return 0;
    }
    if (skip.trim().toLowerCase() === 'y')
        return 0;
    const username = (await readTty('Enter Git username: '))?.replace(/\r/g, '').trim();
    if (!username)
        throw new Error('Git username was not provided');
    gitConfig(['user.name', username]);
    const email = (await readTty('Enter Git email: '))?.replace(/\r/g, '').trim();
    if (!email)
        throw new Error('Git email was not provided');
    gitConfig(['user.email', email]);
    return 0;
}
