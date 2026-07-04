#!/usr/bin/env node
/**
 * 终端多选 — 交互模式参考 @clack/core（vite-plus prompts 底层），仅用 Node 内置模块。
 */
import { execSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'
import tty from 'node:tty'
import { fileURLToPath } from 'node:url'
import { formatLocalDisplay, formatRepoDisplay } from './sync-pairs.mjs'

function parseItems(rawLines) {
  return rawLines.map((line) => {
    const [local, repo, backup] = line.split('\t')
    return { local, repo, backup, selected: true, line }
  })
}

function writeResult(lines, outPath) {
  const content = `${lines.join('\n')}\n`
  if (outPath) fs.writeFileSync(outPath, content)
  else process.stdout.write(content)
}

function openWindowsConsole() {
  try {
    const fdIn = fs.openSync('CONIN$', 'r')
    const fdOut = fs.openSync('CONOUT$', 'w')
    return {
      input: new tty.ReadStream(fdIn),
      output: new tty.WriteStream(fdOut),
      owned: true,
      close() {
        if (!this.input.destroyed) this.input.destroy()
        if (!this.output.destroyed) this.output.destroy()
      },
    }
  }
  catch {
    return null
  }
}

function openTerminal() {
  if (process.stdin.isTTY && process.stdout.isTTY) {
    return {
      input: process.stdin,
      output: process.stdout,
      owned: false,
      close() {},
    }
  }

  if (process.platform === 'win32') {
    if (process.env.SYNC_INTERACTIVE === '1') {
      return openWindowsConsole()
    }
    if (process.stdin.isTTY) {
      return {
        input: process.stdin,
        output: process.stdout,
        owned: false,
        close() {},
      }
    }
    return null
  }

  try {
    const fd = fs.openSync('/dev/tty', 'r+')
    return {
      input: new tty.ReadStream(fd),
      output: new tty.WriteStream(fd),
      owned: true,
      close() {
        if (!this.input.destroyed) this.input.destroy()
        if (!this.output.destroyed) this.output.destroy()
      },
    }
  }
  catch {
    return null
  }
}

function columns(output) {
  if (output.columns && output.columns > 0) return output.columns
  if (process.platform !== 'win32') {
    try {
      const [, cols] = execSync('stty size', { encoding: 'utf8' }).trim().split(/\s+/)
      const n = Number.parseInt(cols, 10)
      if (n > 0) return n
    }
    catch {}
  }
  return 80
}

function truncate(text, max) {
  if (text.length <= max) return text
  const head = Math.floor((max - 1) / 2)
  const tail = max - 1 - head
  return `${text.slice(0, head)}…${text.slice(-tail)}`
}

function frameLines(frame) {
  if (!frame) return 0
  return Math.max(0, frame.split('\n').length - 1)
}

function restoreFrame(output, frame) {
  const up = frameLines(frame)
  if (up > 0) output.write(`\x1B[${up}A\r`)
}

function isToggleKey(str, key) {
  return str === ' ' || key?.name === 'space' || key?.name === 'x'
}

function createMultiselect({ message, choices, input, output }) {
  let cursor = 0
  let prevFrame = ''
  let state = 'active'
  let error = ''
  /** @type {import('node:readline').Interface | undefined} */
  let rl

  function renderActiveFrame() {
    const width = columns(output)
    const labelMax = Math.max(30, width - 8)
    const lines = [
      message,
      '',
      ...choices.map((item, i) => {
        const mark = item.selected ? '✓' : ' '
        const pointer = i === cursor ? '❯' : ' '
        return `${pointer} [${mark}] ${truncate(item.label, labelMax)}`
      }),
      '',
      '↑↓ 移动  空格/x 切换  回车 确认',
    ]
    if (error) lines.push('', error)
    return `${lines.join('\n')}\n`
  }

  function renderSubmitFrame() {
    const picked = choices.filter((c) => c.selected)
    return `${message}\n\n已选 ${picked.length} 项\n`
  }

  function render() {
    const frame = state === 'submit' ? renderSubmitFrame() : renderActiveFrame()
    if (frame === prevFrame) return

    if (prevFrame) {
      restoreFrame(output, prevFrame)
      output.write('\x1B[J')
    }
    else {
      output.write('\x1B[?25l')
    }

    output.write(frame)
    prevFrame = frame
  }

  return new Promise((resolve, reject) => {
    const canInteract = input.isTTY || process.env.SYNC_INTERACTIVE === '1'
    if (!canInteract) {
      reject(new Error('非 TTY 环境'))
      return
    }

    try {
      if (typeof input.setRawMode === 'function') {
        input.setRawMode(true)
      }
    }
    catch (err) {
      reject(new Error(`无法进入交互模式: ${err.message}`))
      return
    }

    rl = readline.createInterface({
      input,
      terminal: true,
      prompt: '',
    })
    rl.prompt()

    const close = () => {
      input.removeListener('keypress', onKeypress)
      output.write('\n')
      output.write('\x1B[?25h')
      if (typeof input.setRawMode === 'function') {
        input.setRawMode(false)
      }
      rl?.close()
      rl = undefined
    }

    const onKeypress = (str, key) => {
      if (state === 'submit') return

      if (isToggleKey(str, key)) {
        choices[cursor].selected = !choices[cursor].selected
        error = ''
        render()
        return
      }

      if (!key) return

      if (key.name === 'return' || key.name === 'enter') {
        const picked = choices.filter((c) => c.selected)
        if (picked.length === 0) {
          error = '至少选择一项'
          render()
          return
        }
        error = ''
        state = 'submit'
        render()
        close()
        resolve(picked)
        return
      }

      if (key.name === 'up') {
        cursor = (cursor - 1 + choices.length) % choices.length
      }
      else if (key.name === 'down') {
        cursor = (cursor + 1) % choices.length
      }
      else if (key.ctrl && key.name === 'c') {
        close()
        const err = new Error('文件选择已取消')
        err.code = 'CANCELLED'
        reject(err)
        return
      }
      else {
        return
      }

      render()
    }

    input.on('keypress', onKeypress)
    render()
  })
}

export async function runSyncSelectPrompt({ direction, rawLines, outPath }) {
  const items = parseItems(rawLines)

  if (items.length === 0) {
    writeResult(rawLines, outPath)
    return 0
  }

  const term = openTerminal()
  if (!term) {
    if (process.env.SYNC_INTERACTIVE === '1') {
      throw new Error('无法打开交互终端，请使用 SYNC_SELECT_ALL=1 跳过选择')
    }
    writeResult(rawLines, outPath)
    return rawLines.length
  }

  const title = direction === '1' ? '选择要备份到仓库的文件' : '选择要恢复到本地的文件'
  const choices = items.map((item) => ({
    label: direction === '1' ? formatRepoDisplay(item.repo) : formatLocalDisplay(item.local),
    selected: item.selected,
    line: item.line,
  }))

  try {
    const picked = await createMultiselect({
      message: title,
      choices,
      input: term.input,
      output: term.output,
    })
    writeResult(picked.map((c) => c.line), outPath)
    return picked.length
  }
  catch (err) {
    if (process.env.SYNC_INTERACTIVE === '1') {
      throw err
    }
    writeResult(rawLines, outPath)
    return rawLines.length
  }
  finally {
    term.close()
  }
}

const isCli = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (isCli) {
  const direction = process.argv[2]
  const pairsPath = process.argv[3]
  const outPath = process.argv[4]

  if (!direction || !pairsPath) {
    console.error('用法: node sync-select.mjs <1|2> <pairs-file> [out-file]')
    process.exit(1)
  }

  const rawLines = fs.readFileSync(pairsPath, 'utf8').trim().split('\n').filter(Boolean)

  try {
    await runSyncSelectPrompt({ direction, rawLines, outPath })
  }
  catch (err) {
    if (err.code === 'CANCELLED') process.exit(130)
    console.error(err?.message || String(err))
    process.exit(1)
  }
}
