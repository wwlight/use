export function stripDashArgs(args = []) {
    return args.filter((arg) => arg !== '--');
}
export function isHelpFlag(args = []) {
    return args.some((arg) => ['-h', '--help', 'help'].includes(arg));
}
/** First positional value; a leading `--name` is stripped to `name`. */
export function firstValueArg(args = []) {
    const clean = stripDashArgs(args);
    let value = clean[0] || '';
    if (value.startsWith('--'))
        value = value.slice(2);
    return value;
}
