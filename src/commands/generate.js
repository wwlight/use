import { canceled, step, stepSuccess, error } from "../core/log.js";
import { canOpenTerminal } from "../lib/tty-term.js";
import { formatAlignedChoices, runMenuSelect } from "../lib/menu-select.js";
import { generateBrewMirrorFiles } from "../generate/brew-mirror.js";
import { generateGithubAccelFiles } from "../generate/github-accel.js";
const GENERATORS = [
    {
        value: 'github-accel',
        detail: '更新 GitHub 加速配置与 README(mirrors → 生成内容)',
        run: generateGithubAccelFiles,
        done: 'GitHub acceleration content updated',
    },
    {
        value: 'brew-mirror',
        detail: '更新 Homebrew 镜像目录 mirrors.tsv',
        run: generateBrewMirrorFiles,
        done: 'Brew mirror catalog updated',
    },
];
async function runGenerator(value) {
    const targets = value === 'all'
        ? GENERATORS
        : GENERATORS.filter((item) => item.value === value);
    if (targets.length === 0)
        throw new Error(`Unknown generate target: ${value}`);
    for (const gen of targets) {
        step(`Generating ${gen.value}...`);
        gen.run();
        stepSuccess(gen.done);
    }
    return 0;
}
export async function runGenerateCommand(args = []) {
    const clean = args.filter((arg) => arg !== '--');
    if (clean[0] === '-h' || clean[0] === '--help' || clean[0] === 'help') {
        console.log([
            'Usage: vpr generate [all|<target>]',
            '',
            'Regenerate files derived from the manifests:',
            '  all            生成全部产物',
            ...GENERATORS.map((item) => `  ${item.value.padEnd(14)} ${item.detail}`),
            '',
            'Run without a target to choose interactively.',
        ].join('\n'));
        return 0;
    }
    if (clean[0])
        return runGenerator(clean[0]);
    if (!canOpenTerminal()) {
        error('Pass a target in non-interactive environments (example: vpr generate all)');
        return 1;
    }
    try {
        const choice = await runMenuSelect({
            message: 'Choose what to generate',
            choices: formatAlignedChoices([
                { value: 'all', name: 'all', detail: '生成全部产物' },
                ...GENERATORS.map((item) => ({
                    value: item.value,
                    name: item.value,
                    detail: item.detail,
                })),
            ]),
        });
        return runGenerator(String(choice));
    }
    catch (err) {
        if (err?.code === 'CANCELLED') {
            if (!err.printed)
                canceled();
            return 130;
        }
        throw err;
    }
}
