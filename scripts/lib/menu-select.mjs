#!/usr/bin/env node
/**
 * Terminal single-select menu: move with arrows and confirm with Enter.
 * Usage: node menu-select.mjs <title> <value) description> [value) description ...]
 */
import path from 'node:path'
import fs from 'node:fs'
import readline from 'node:readline'
import { fileURLToPath } from 'node:url'
import { frameLines, openTerminal, restoreFrame } from './tty-term.mjs'

function clearPreviousFrame(output, frame) {
  const lines = frameLines(frame)
  if (lines <= 0) return
  restoreFrame(output, frame)
  for (let i = 0; i < lines; i++) {
    output.write('\x1B[2K')
    if (i < lines - 1) output.write('\n')
  }
  if (lines > 1) output.write(`\x1B[${lines - 1}A\r`)
  else output.write('\r')
}

function createSelect({ message, choices, input, output, cursor: initialCursor = 0 }) {
  let cursor = Math.min(Math.max(0, initialCursor), Math.max(0, choices.length - 1))
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
      '↑↓ Select  Enter Confirm',
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
      // Clear only the menu region; \x1B[J would clear the entire screen.
      clearPreviousFrame(output, prevFrame)
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
      reject(new Error(`Could not enter interactive mode: ${err.message}`))
      return
    }

    // Do not bind output / terminal:true; readline adds a newline and offsets restoreFrame.
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
        const err = new Error('Canceled')
        err.code = 'CANCELLED'
        reject(err)
        return
      }
      else if (key.name === 'escape') {
        close()
        const err = new Error('Canceled')
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
    throw new Error(`Expected option format "value) description"; received: ${raw}`)
  }
  return {
    value: raw.slice(0, idx).trim(),
    label: raw,
  }
}

export async function runMenuSelect({ message, choices, initialValue }) {
  const term = openTerminal({ allowWindowsConsole: true })
  if (!term) {
    throw new Error('Could not open an interactive terminal')
  }

  try {
    let cursor = 0
    if (initialValue != null && initialValue !== '') {
      const idx = choices.findIndex((item) => String(item.value) === String(initialValue))
      if (idx >= 0) cursor = idx
    }
    return await createSelect({
      message,
      choices,
      input: term.input,
      output: term.output,
      cursor,
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
    console.error('Usage: node menu-select.mjs <title> <value) description> [value) description ...]')
    process.exit(1)
  }

  try {
    const choices = rawChoices.map(parseChoice)
    const value = await runMenuSelect({
      message,
      choices,
      initialValue: process.env.MENU_SELECT_INITIAL,
    })
    const text = `${String(value).trim()}\n`
    const outFile = process.env.MENU_SELECT_OUT
    if (outFile) {
      fs.writeFileSync(outFile, text, 'utf8')
    }
    else {
      process.stdout.write(text)
    }
  }
  catch (err) {
    if (err.code === 'CANCELLED') process.exit(130)
    console.error(err?.message || String(err))
    process.exit(1)
  }
}
