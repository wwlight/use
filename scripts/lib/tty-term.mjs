/**
 * 打开可用于交互的终端流（支持 curl|bash / PowerShell 捕获 stdout 场景）。
 */
import fs from 'node:fs'
import tty from 'node:tty'

export function frameLines(frame) {
  if (!frame) return 0
  return Math.max(0, frame.split('\n').length - 1)
}

export function restoreFrame(output, frame) {
  const up = frameLines(frame)
  if (up > 0) output.write(`\x1B[${up}A\r`)
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

/**
 * @param {{ allowWindowsConsole?: boolean }} [options]
 * - allowWindowsConsole: Windows 下 stdout 非 TTY 时是否打开 CONIN$/CONOUT$
 *   默认跟随 SYNC_INTERACTIVE=1（与 sync-select 一致）
 */
export function openTerminal(options = {}) {
  const allowWindowsConsole = options.allowWindowsConsole
    ?? process.env.SYNC_INTERACTIVE === '1'

  if (process.stdin.isTTY && process.stdout.isTTY) {
    return {
      input: process.stdin,
      output: process.stdout,
      owned: false,
      close() {},
    }
  }

  if (process.platform === 'win32') {
    if (allowWindowsConsole) {
      const cons = openWindowsConsole()
      if (cons) return cons
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
