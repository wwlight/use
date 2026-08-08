#!/usr/bin/env node
/**
 * GitHub accel blocks: install.sh/ps1, github-accel.zsh, README docs.
 * CLI: node src/generate/github-accel.js [--check]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { projectRoot } from "../core/paths.js";

const MARKERS = {
    code: {
        start: '# BEGIN GENERATED GITHUB ACCEL',
        end: '# END GENERATED GITHUB ACCEL',
    },
    docs: {
        start: '<!-- BEGIN GENERATED GITHUB ACCEL DOCS -->',
        end: '<!-- END GENERATED GITHUB ACCEL DOCS -->',
    },
    windowsPm: {
        start: '<!-- BEGIN GENERATED GITHUB ACCEL WINDOWS PM -->',
        end: '<!-- END GENERATED GITHUB ACCEL WINDOWS PM -->',
    },
    scoopMirror: {
        start: '<!-- BEGIN GENERATED GITHUB ACCEL SCOOP MIRROR -->',
        end: '<!-- END GENERATED GITHUB ACCEL SCOOP MIRROR -->',
    },
};

function loadMirrors(root) {
    const manifestPath = path.join(root, 'manifests/common.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const config = manifest.githubAccel;
    if (!config || !Array.isArray(config.mirrors) || config.mirrors.length === 0) {
        throw new Error('common manifest githubAccel.mirrors must not be empty');
    }
    const seenIds = new Set();
    const seenPrefixes = new Set();
    const mirrors = config.mirrors.map((item) => {
        const id = String(item?.id || '').trim();
        let prefix = String(item?.prefix || '').trim();
        if (!id || !prefix)
            throw new Error('githubAccel mirrors must include id and prefix');
        if (/[\r\n'"]/.test(prefix))
            throw new Error(`githubAccel prefix contains unsupported characters: ${prefix}`);
        if (!prefix.endsWith('/'))
            prefix += '/';
        if (seenIds.has(id))
            throw new Error(`Duplicate githubAccel mirror id: ${id}`);
        if (seenPrefixes.has(prefix))
            throw new Error(`Duplicate githubAccel mirror prefix: ${prefix}`);
        seenIds.add(id);
        seenPrefixes.add(prefix);
        return { id, prefix };
    });
    const defaultId = String(config.default || '').trim();
    const defaultMirror = mirrors.find((item) => item.id === defaultId);
    if (!defaultMirror)
        throw new Error(`githubAccel.default is not present in mirrors: ${defaultId}`);
    return [defaultMirror, ...mirrors.filter((item) => item !== defaultMirror)];
}

function replaceBlock(content, markers, body, relativePath) {
    const startIndex = content.indexOf(markers.start);
    const endIndex = content.indexOf(markers.end);
    if (startIndex < 0 || endIndex < 0 || endIndex < startIndex) {
        throw new Error(`${relativePath} is missing complete generated markers`);
    }
    if (content.indexOf(markers.start, startIndex + markers.start.length) >= 0
        || content.indexOf(markers.end, endIndex + markers.end.length) >= 0) {
        throw new Error(`${relativePath} contains duplicate generated markers`);
    }
    const generated = `${markers.start}\n${body}\n${markers.end}`;
    return content.slice(0, startIndex) + generated + content.slice(endIndex + markers.end.length);
}

function shellConfig(mirrors) {
    return [
        'GITHUB_ACCEL_IDS=(',
        ...mirrors.map(({ id }) => `  "${id}"`),
        ')',
        'GITHUB_ACCEL_PREFIXES=(',
        ...mirrors.map(({ prefix }) => `  "${prefix}"`),
        ')',
    ].join('\n');
}

function powershellConfig(mirrors) {
    return [
        '$GithubAccelIds = @(',
        ...mirrors.map(({ id }, index) => `    '${id}'${index < mirrors.length - 1 ? ',' : ''}`),
        ')',
        '$GithubAccelPrefixes = @(',
        ...mirrors.map(({ prefix }, index) => `    '${prefix}'${index < mirrors.length - 1 ? ',' : ''}`),
        ')',
    ].join('\n');
}

function zshConfig(mirrors) {
    return [
        'typeset -ga GITHUB_ACCEL_MIRRORS=(',
        ...mirrors.map(({ prefix }) => `  '${prefix}'`),
        ')',
    ].join('\n');
}

function codeBlock(language, command) {
    return `\`\`\`${language}\n${command}\n\`\`\``;
}

function commandVariants(officialUrl, mirrors, format) {
    return [
        { url: officialUrl, accel: null },
        ...mirrors.map(({ id, prefix }) => ({ url: `${prefix}${officialUrl}`, accel: id })),
    ]
        .map(({ url, accel }) => codeBlock(format.language, format.command(url, accel)))
        .join('\n\n');
}

function shInstallCommand(url, accel, profile) {
    const args = profile ? ` -s -- ${profile}` : '';
    if (!accel)
        return `curl -fsSL ${url} | bash${args}`;
    return `curl -fsSL ${url} | USE_ACCEL=${accel} bash${args}`;
}

function psInstallCommand(url, accel, profile) {
    const parts = [];
    if (profile)
        parts.push(`$env:USE_PROFILE='${profile}'`);
    if (accel)
        parts.push(`$env:USE_ACCEL='${accel}'`);
    parts.push(`irm ${url} | iex`);
    return parts.join('; ');
}

function hostLabel(prefix) {
    try {
        return new URL(prefix).host;
    }
    catch {
        return prefix.replace(/^https?:\/\//, '').replace(/\/$/, '');
    }
}

function padComment(command, width) {
    return command.padEnd(width);
}

function windowsPmDocs(mirrors) {
    const width = 34;
    const lines = [
        `${padComment('vpr pm', width)}# 安装 scoop，交互选加速镜像`,
        ...mirrors.map(({ id, prefix }) => (
            `${padComment(`vpr pm -- ${id}`, width)}# ${hostLabel(prefix)} 加速镜像`
        )),
        `${padComment('vpr pm -- official', width)}# 官方源`,
        `${padComment('vpr init', width)}# 初始化（会启用已选加速）`,
        `${padComment('vpr init -- lite', width)}# 尝鲜版`,
        `${padComment('vpr init -- full', width)}# 完整版`,
    ];
    return codeBlock('sh', lines.join('\n'));
}

function scoopMirrorDocs(mirrors) {
    const width = 34;
    const lines = [
        `${padComment('scoop mirror', width)}# 交互选择（↑↓ / Enter；Esc/Ctrl+C 取消；回车选中当前 * 则直接退出）`,
        `${padComment('scoop mirror status', width)}# 显示当前镜像与下载规则`,
        ...mirrors.map(({ id, prefix }) => (
            `${padComment(`scoop mirror ${id}`, width)}# 直接切换到 ${hostLabel(prefix)}`
        )),
        `${padComment('scoop mirror official', width)}# 恢复官方源`,
    ];
    return [
        '一键同步切换 Scoop 仓库、GitHub bucket 远端及后续安装、更新使用的下载镜像（仓库侧见上方 `runtime/scoop/`）。',
        '',
        '运行时在 `$SCOOP/config/scoop-mirror/` 生成 `config.json`；菜单依赖同步到同目录 `lib/`。',
        '',
        '下载规则：已选镜像 → 其他镜像 → 官方（非 GitHub URL 直连）。`scoop mirror` 只改首选；真正下载仍按该顺序 fallback。',
        '',
        codeBlock('sh', lines.join('\n')),
    ].join('\n');
}

function readmeDocs(mirrors) {
    const useBase = 'https://raw.githubusercontent.com/wwlight/use/main';
    const viteBase = 'https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli';
    const sections = [
        '使用需要 Node.js 环境。',
        '',
        '## 前置：安装 [vite.plus](https://viteplus.dev/)',
        '',
        '### macos',
        '',
        codeBlock('sh', 'curl -fsSL https://vite.plus | bash'),
        '',
        mirrors
            .map(({ prefix }) => codeBlock('sh', `curl -fsSL ${prefix}${viteBase}/install.sh | bash`))
            .join('\n\n'),
        '',
        '### windows',
        '',
        codeBlock('powershell', 'irm https://vite.plus/ps1 | iex'),
        '',
        mirrors
            .map(({ prefix }) => codeBlock('powershell', `irm ${prefix}${viteBase}/install.ps1 | iex`))
            .join('\n\n'),
        '',
        '',
        '## 一键安装',
        '',
        '### macos · 交互选择',
        '',
        commandVariants(`${useBase}/install.sh`, mirrors, {
            language: 'sh',
            command: (url, accel) => shInstallCommand(url, accel, null),
        }),
        '',
        '### macos · 尝鲜版',
        '',
        commandVariants(`${useBase}/install.sh`, mirrors, {
            language: 'sh',
            command: (url, accel) => shInstallCommand(url, accel, 'lite'),
        }),
        '',
        '### macos · 完整版',
        '',
        commandVariants(`${useBase}/install.sh`, mirrors, {
            language: 'sh',
            command: (url, accel) => shInstallCommand(url, accel, 'full'),
        }),
        '',
        '### windows · 执行策略',
        '',
        codeBlock('powershell', 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser'),
        '',
        '### windows · 交互选择',
        '',
        commandVariants(`${useBase}/install.ps1`, mirrors, {
            language: 'powershell',
            command: (url, accel) => psInstallCommand(url, accel, null),
        }),
        '',
        '### windows · 尝鲜版',
        '',
        commandVariants(`${useBase}/install.ps1`, mirrors, {
            language: 'powershell',
            command: (url, accel) => psInstallCommand(url, accel, 'lite'),
        }),
        '',
        '### windows · 完整版',
        '',
        commandVariants(`${useBase}/install.ps1`, mirrors, {
            language: 'powershell',
            command: (url, accel) => psInstallCommand(url, accel, 'full'),
        }),
    ];
    return sections.join('\n');
}

function updateGeneratedFile(root, relativePath, markers, body, write) {
    const filePath = path.join(root, relativePath);
    const current = fs.readFileSync(filePath, 'utf8');
    const expected = replaceBlock(current, markers, body, relativePath);
    if (current === expected)
        return false;
    if (write)
        fs.writeFileSync(filePath, expected);
    return true;
}

function applyGithubAccelGenerated(root, { write }) {
    const mirrors = loadMirrors(root);
    return [
        updateGeneratedFile(root, 'install.sh', MARKERS.code, shellConfig(mirrors), write),
        updateGeneratedFile(root, 'install.ps1', MARKERS.code, powershellConfig(mirrors), write),
        updateGeneratedFile(root, 'configs/common/github-accel.zsh', MARKERS.code, zshConfig(mirrors), write),
        updateGeneratedFile(root, 'README.md', MARKERS.docs, readmeDocs(mirrors), write),
        updateGeneratedFile(root, 'README.md', MARKERS.windowsPm, windowsPmDocs(mirrors), write),
        updateGeneratedFile(root, 'README.md', MARKERS.scoopMirror, scoopMirrorDocs(mirrors), write),
    ];
}

/** @returns {{ ok: true } | { ok: false, reason: string }} */
export function checkGithubAccelGenerated(root = projectRoot()) {
    const changed = applyGithubAccelGenerated(root, { write: false });
    if (changed.some(Boolean)) {
        return {
            ok: false,
            reason: 'Generated GitHub acceleration content is stale; run: npm run generate:github-accel',
        };
    }
    return { ok: true };
}

export function generateGithubAccelFiles(root = projectRoot()) {
    const changed = applyGithubAccelGenerated(root, { write: true });
    return { updated: changed.some(Boolean) };
}

function main() {
    if (process.argv.includes('--check')) {
        const result = checkGithubAccelGenerated();
        if (!result.ok) {
            console.error(result.reason);
            process.exit(1);
        }
        console.log('Generated GitHub acceleration content is current');
        return;
    }
    generateGithubAccelFiles();
    console.log('Generated GitHub acceleration content updated');
}

const isDirectRun = Boolean(process.argv[1])
    && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun)
    main();
