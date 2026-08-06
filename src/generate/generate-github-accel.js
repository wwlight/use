#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { projectRoot } from "../core/paths.js";
const root = projectRoot();
const manifestPath = path.join(root, 'manifests/common.json');
const checkOnly = process.argv.includes('--check');
const MARKERS = {
    code: {
        start: '# BEGIN GENERATED GITHUB ACCEL',
        end: '# END GENERATED GITHUB ACCEL',
    },
    docs: {
        start: '<!-- BEGIN GENERATED GITHUB ACCEL DOCS -->',
        end: '<!-- END GENERATED GITHUB ACCEL DOCS -->',
    },
};
function loadMirrors() {
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
function readmeDocs(mirrors) {
    const useBase = 'https://raw.githubusercontent.com/wwlight/use/main';
    const viteBase = 'https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli';
    const sections = [
        '使用需要 Node.js 环境。',
        '',
        '## 安装 [vite.plus](https://viteplus.dev/)',
        '',
        '仓库：https://github.com/voidzero-dev/vite-plus',
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
function updateGeneratedFile(relativePath, markers, body) {
    const filePath = path.join(root, relativePath);
    const current = fs.readFileSync(filePath, 'utf8');
    const expected = replaceBlock(current, markers, body, relativePath);
    if (current === expected)
        return false;
    if (!checkOnly)
        fs.writeFileSync(filePath, expected);
    return true;
}
const mirrors = loadMirrors();
const changed = [
    updateGeneratedFile('install.sh', MARKERS.code, shellConfig(mirrors)),
    updateGeneratedFile('install.ps1', MARKERS.code, powershellConfig(mirrors)),
    updateGeneratedFile('configs/common/github-accel.zsh', MARKERS.code, zshConfig(mirrors)),
    updateGeneratedFile('README.md', MARKERS.docs, readmeDocs(mirrors)),
];
if (checkOnly && changed.some(Boolean)) {
    console.error('Generated GitHub acceleration content is stale; run: npm run generate:github-accel');
    process.exit(1);
}
console.log(checkOnly ? 'Generated GitHub acceleration content is current' : 'Generated GitHub acceleration content updated');
