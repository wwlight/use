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
        // 只关输入；destroy CONOUT$ 易导致控制台被清空/错乱
        if (!this.input.destroyed) this.input.destroy()
      },
    }
  }
  catch {
    return null
  }
}

function isVsCodeConPty() {
  const term = String(process.env.TERM_PROGRAM || '').toLowerCase()
  return term === 'vscode' || term === 'cursor' || Boolean(process.env.VSCODE_INJECTION)
}

/**
 * @param {{ allowWindowsConsole?: boolean }} [options]
 * - allowWindowsConsole: Windows 下是否允许 CONIN$/CONOUT$
 *   默认跟随 SYNC_INTERACTIVE=1；Cursor/VS Code ConPTY 下禁用（菜单不可见会假死）
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

  // PowerShell `$x = & node ...` 会捕获 stdout；stderr 仍常是 TTY，菜单应画在这里
  if (process.stdin.isTTY && process.stderr.isTTY) {
    return {
      input: process.stdin,
      output: process.stderr,
      owned: false,
      close() {},
    }
  }

  if (process.platform === 'win32') {
    // Cursor/VS Code 的 ConPTY 下 CONOUT$ 不可见、CONIN$ 收不到按键 → 表现为卡住
    if (allowWindowsConsole && !isVsCodeConPty()) {
      const cons = openWindowsConsole()
      if (cons) return cons
    }
    if (process.stdin.isTTY) {
      return {
        input: process.stdin,
        output: process.stderr.isTTY ? process.stderr : process.stdout,
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
