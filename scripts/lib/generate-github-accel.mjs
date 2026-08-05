import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const manifestPath = path.join(projectRoot, 'scripts/common/_manifest.json')
const checkOnly = process.argv.includes('--check')

const MARKERS = {
  code: {
    start: '# BEGIN GENERATED GITHUB ACCEL',
    end: '# END GENERATED GITHUB ACCEL',
  },
  docs: {
    start: '<!-- BEGIN GENERATED GITHUB ACCEL DOCS -->',
    end: '<!-- END GENERATED GITHUB ACCEL DOCS -->',
  },
}

function loadMirrors() {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  const config = manifest.githubAccel
  if (!config || !Array.isArray(config.mirrors) || config.mirrors.length === 0) {
    throw new Error('common manifest 的 githubAccel.mirrors 不能为空')
  }

  const seenIds = new Set()
  const seenPrefixes = new Set()
  const mirrors = config.mirrors.map((item) => {
    const id = String(item?.id || '').trim()
    let prefix = String(item?.prefix || '').trim()
    if (!id || !prefix) throw new Error('githubAccel mirror 必须包含 id 和 prefix')
    if (/[\r\n'"]/.test(prefix)) throw new Error(`githubAccel prefix 包含不支持的字符: ${prefix}`)
    if (!prefix.endsWith('/')) prefix += '/'
    if (seenIds.has(id)) throw new Error(`githubAccel mirror id 重复: ${id}`)
    if (seenPrefixes.has(prefix)) throw new Error(`githubAccel mirror prefix 重复: ${prefix}`)
    seenIds.add(id)
    seenPrefixes.add(prefix)
    return { id, prefix }
  })

  const defaultId = String(config.default || '').trim()
  const defaultMirror = mirrors.find((item) => item.id === defaultId)
  if (!defaultMirror) throw new Error(`githubAccel.default 不存在于 mirrors: ${defaultId}`)

  return [defaultMirror, ...mirrors.filter((item) => item !== defaultMirror)]
}

function replaceBlock(content, markers, body, relativePath) {
  const startIndex = content.indexOf(markers.start)
  const endIndex = content.indexOf(markers.end)
  if (startIndex < 0 || endIndex < 0 || endIndex < startIndex) {
    throw new Error(`${relativePath} 缺少完整生成标记`)
  }
  if (content.indexOf(markers.start, startIndex + markers.start.length) >= 0
    || content.indexOf(markers.end, endIndex + markers.end.length) >= 0) {
    throw new Error(`${relativePath} 包含重复生成标记`)
  }

  const generated = `${markers.start}\n${body}\n${markers.end}`
  return content.slice(0, startIndex) + generated + content.slice(endIndex + markers.end.length)
}

function shellConfig(mirrors) {
  return [
    'GITHUB_ACCEL_PREFIXES=(',
    ...mirrors.map(({ prefix }) => `  "${prefix}"`),
    ')',
  ].join('\n')
}

function powershellConfig(mirrors) {
  return [
    '$GithubAccelPrefixes = @(',
    ...mirrors.map(({ prefix }, index) => `    '${prefix}'${index < mirrors.length - 1 ? ',' : ''}`),
    ')',
  ].join('\n')
}

function zshConfig(mirrors) {
  return [
    'typeset -ga GITHUB_ACCEL_MIRRORS=(',
    ...mirrors.map(({ prefix }) => `  '${prefix}'`),
    ')',
  ].join('\n')
}

function codeBlock(language, command) {
  return `\`\`\`${language}\n${command}\n\`\`\``
}

function commandVariants(officialUrl, mirrors, format) {
  return [officialUrl, ...mirrors.map(({ prefix }) => `${prefix}${officialUrl}`)]
    .map((url) => codeBlock(format.language, format.command(url)))
    .join('\n\n')
}

function readmeDocs(mirrors) {
  const useBase = 'https://raw.githubusercontent.com/wwlight/use/main'
  const viteBase = 'https://raw.githubusercontent.com/voidzero-dev/vite-plus/main/packages/cli'
  const sections = [
    '## 一键安装',
    '',
    '### macos · 交互选择',
    '',
    commandVariants(`${useBase}/install.sh`, mirrors, {
      language: 'sh',
      command: (url) => `curl -fsSL ${url} | bash`,
    }),
    '',
    '### macos · 尝鲜版',
    '',
    commandVariants(`${useBase}/install.sh`, mirrors, {
      language: 'sh',
      command: (url) => `curl -fsSL ${url} | bash -s -- lite`,
    }),
    '',
    '### macos · 完整版',
    '',
    commandVariants(`${useBase}/install.sh`, mirrors, {
      language: 'sh',
      command: (url) => `curl -fsSL ${url} | bash -s -- full`,
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
      command: (url) => `irm ${url} | iex`,
    }),
    '',
    '### windows · 尝鲜版',
    '',
    commandVariants(`${useBase}/install.ps1`, mirrors, {
      language: 'powershell',
      command: (url) => `$env:USE_PROFILE='lite'; irm ${url} | iex`,
    }),
    '',
    '### windows · 完整版',
    '',
    commandVariants(`${useBase}/install.ps1`, mirrors, {
      language: 'powershell',
      command: (url) => `$env:USE_PROFILE='full'; irm ${url} | iex`,
    }),
    '',
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
  ]
  return sections.join('\n')
}

function updateGeneratedFile(relativePath, markers, body) {
  const filePath = path.join(projectRoot, relativePath)
  const current = fs.readFileSync(filePath, 'utf8')
  const expected = replaceBlock(current, markers, body, relativePath)
  if (current === expected) return false
  if (!checkOnly) fs.writeFileSync(filePath, expected)
  return true
}

const mirrors = loadMirrors()
const changed = [
  updateGeneratedFile('install.sh', MARKERS.code, shellConfig(mirrors)),
  updateGeneratedFile('install.ps1', MARKERS.code, powershellConfig(mirrors)),
  updateGeneratedFile('configs/common/github-accel.zsh', MARKERS.code, zshConfig(mirrors)),
  updateGeneratedFile('README.md', MARKERS.docs, readmeDocs(mirrors)),
]

if (checkOnly && changed.some(Boolean)) {
  console.error('GitHub 加速生成内容已过期，请运行: npm run generate:github-accel')
  process.exit(1)
}

console.log(checkOnly ? 'GitHub 加速生成内容检查通过' : 'GitHub 加速生成内容已更新')
