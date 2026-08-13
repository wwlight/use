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
/**
 * Resolve a positional subcommand with help handling. Returns `helpValue`
 * when a help flag is present, otherwise the first positional value (a
 * leading `--name` is stripped to `name`).
 */
export function resolveChoiceArg(args = [], helpValue = '__HELP__') {
    if (isHelpFlag(args))
        return helpValue;
    return firstValueArg(args);
}
