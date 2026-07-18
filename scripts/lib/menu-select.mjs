#!/usr/bin/env node
/**
 * 终端单选菜单 — ↑↓ 移动，回车确认。结果写到 stdout。
 * 用法: node menu-select.mjs <标题> <value) 说明> [value) 说明 ...]
 */
import path from 'node:path'
import readline from 'node:readline'
import { fileURLToPath } from 'node:url'
import { openTerminal, restoreFrame } from './tty-term.mjs'

function createSelect({ message, choices, input, output }) {
  let cursor = 0
  let prevFrame = ''
  let state = 'active'
  /** @type {import('node:readline').Interface | undefined} */
  let rl

  function renderActiveFrame() {
    const lines = [
      message,
      '',
      ...choices.map((item, i) => {
        const pointer = i === cursor ? '❯' : ' '
        return `${pointer} ${item.label}`
      }),
      '',
      '↑↓ 选择  回车 确认',
    ]
    return `${lines.join('\n')}\n`
  }

  function renderSubmitFrame() {
    return `${message}\n❯ ${choices[cursor].label}\n`
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
    try {
      if (typeof input.setRawMode === 'function') {
        input.setRawMode(true)
      }
    }
    catch (err) {
      reject(new Error(`无法进入交互模式: ${err.message}`))
      return
    }

    // 勿绑 output / terminal:true，否则回车时 readline 会多写换行，restoreFrame 错位
    rl = readline.createInterface({ input })
    readline.emitKeypressEvents(input, rl)

    const close = ({ endLine = true } = {}) => {
      input.removeListener('keypress', onKeypress)
      if (endLine) output.write('\n')
      output.write('\x1B[?25h')
      if (typeof input.setRawMode === 'function') {
        input.setRawMode(false)
      }
      rl?.close()
      rl = undefined
    }

    const onKeypress = (_str, key) => {
      if (state === 'submit' || !key) return

      if (key.name === 'return' || key.name === 'enter') {
        state = 'submit'
        render()
        close({ endLine: false })
        resolve(String(choices[cursor].value).trim())
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
        const err = new Error('已取消')
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

export function parseChoice(raw) {
  const idx = raw.indexOf(')')
  if (idx <= 0) {
    throw new Error(`选项格式应为 value) 说明，收到: ${raw}`)
  }
  return {
    value: raw.slice(0, idx).trim(),
    label: raw,
  }
}

export async function runMenuSelect({ message, choices }) {
  const term = openTerminal({ allowWindowsConsole: true })
  if (!term) {
    throw new Error('无法打开交互终端')
  }

  try {
    return await createSelect({
      message,
      choices,
      input: term.input,
      output: term.output,
    })
  }
  finally {
    term.close()
  }
}

const isCli = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (isCli) {
  const message = process.argv[2]
  const rawChoices = process.argv.slice(3)

  if (!message || rawChoices.length === 0) {
    console.error('用法: node menu-select.mjs <标题> <value) 说明> [value) 说明 ...]')
    process.exit(1)
  }

  try {
    const choices = rawChoices.map(parseChoice)
    const value = await runMenuSelect({ message, choices })
    process.stdout.write(`${String(value).trim()}\n`)
  }
  catch (err) {
    if (err.code === 'CANCELLED') process.exit(130)
    console.error(err?.message || String(err))
    process.exit(1)
  }
}
