/**
 * Terminal display-width helpers (East Asian Width aware).
 * Ambiguous-width glyphs (e.g. ✓) are 2 columns in CJK contexts and 1 elsewhere.
 */
/** @typedef {{ ambiguousWide?: boolean }} WidthOptions */
/**
 * @param {NodeJS.ProcessEnv} [env]
 * @param {string} [intlLocale]
 */
export function resolveAmbiguousWide(env = process.env, intlLocale) {
    const locales = [
        env.LC_ALL,
        env.LC_CTYPE,
        env.LANG,
        intlLocale ?? (typeof Intl !== 'undefined'
            ? Intl.DateTimeFormat().resolvedOptions().locale
            : ''),
    ];
    for (const raw of locales) {
        if (!raw)
            continue;
        const locale = String(raw).split('.')[0];
        if (locale === 'C' || locale === 'POSIX')
            continue;
        if (/^(zh|ja|ko)([-_]|$)/i.test(locale))
            return true;
        if (/[-_](CN|Hans|Hant|JP|KR|TW|HK)\b/i.test(locale))
            return true;
    }
    return false;
}
/** @param {number} cp */
function isControl(cp) {
    return cp <= 0x1f || (cp >= 0x7f && cp <= 0x9f);
}
/** Wide / Fullwidth (W/F) — compact ranges used by typical terminal width libs. */
function isWideCodePoint(cp) {
    return ((cp >= 0x1100 && cp <= 0x115f)
        || cp === 0x2329
        || cp === 0x232a
        || (cp >= 0x2e80 && cp <= 0x303e)
        || (cp >= 0x3040 && cp <= 0xa4cf)
        || (cp >= 0xac00 && cp <= 0xd7a3)
        || (cp >= 0xf900 && cp <= 0xfaff)
        || (cp >= 0xfe10 && cp <= 0xfe19)
        || (cp >= 0xfe30 && cp <= 0xfe6f)
        || (cp >= 0xff00 && cp <= 0xff60)
        || (cp >= 0xffe0 && cp <= 0xffe6)
        || (cp >= 0x1f300 && cp <= 0x1f64f)
        || (cp >= 0x1f900 && cp <= 0x1f9ff)
        || (cp >= 0x20000 && cp <= 0x3fffd));
}
/**
 * Ambiguous (A) characters that matter for this repo's menus / hints / paths.
 * Intentionally not a full UAX #11 table.
 * @param {number} cp
 */
function isAmbiguousCodePoint(cp) {
    return (
    // General punctuation used in sync hints (… — ‘’ “”)
    (cp >= 0x2010 && cp <= 0x2027)
        || (cp >= 0x2030 && cp <= 0x203e)
        // Arrows: ↑ ↓ → etc.
        || (cp >= 0x2190 && cp <= 0x2199)
        // Box drawing / block elements / geometric shapes
        || (cp >= 0x2500 && cp <= 0x25ff)
        // Misc symbols + dingbats: ✓ etc.
        || (cp >= 0x2600 && cp <= 0x27bf));
}
/**
 * @param {number} codePoint
 * @param {boolean} ambiguousWide
 */
export function codePointWidth(codePoint, ambiguousWide = false) {
    if (isControl(codePoint))
        return 0;
    if (codePoint <= 0x7e)
        return 1;
    if (isWideCodePoint(codePoint))
        return 2;
    if (isAmbiguousCodePoint(codePoint))
        return ambiguousWide ? 2 : 1;
    return 1;
}
/**
 * @param {string} text
 * @param {WidthOptions} [options]
 */
export function stringWidth(text, options = {}) {
    const ambiguousWide = options.ambiguousWide ?? resolveAmbiguousWide();
    let width = 0;
    for (const char of String(text ?? '')) {
        width += codePointWidth(char.codePointAt(0), ambiguousWide);
    }
    return width;
}
/**
 * @param {string} text
 * @param {number} target
 * @param {WidthOptions} [options]
 */
export function padEndWidth(text, target, options = {}) {
    const value = String(text ?? '');
    const width = stringWidth(value, options);
    if (width >= target)
        return value;
    return `${value}${' '.repeat(target - width)}`;
}
/**
 * @param {string} text
 * @param {number} max
 * @param {WidthOptions} [options]
 */
export function truncateWidth(text, max, options = {}) {
    const value = String(text ?? '');
    if (max <= 0)
        return '';
    if (stringWidth(value, options) <= max)
        return value;
    const ellipsis = '…';
    const ambiguousWide = options.ambiguousWide ?? resolveAmbiguousWide();
    const widthOpts = { ambiguousWide };
    const ellipsisWidth = stringWidth(ellipsis, widthOpts);
    if (max < ellipsisWidth)
        return '';
    if (max === ellipsisWidth)
        return ellipsis;
    const budget = max - ellipsisWidth;
    const headBudget = Math.floor(budget / 2);
    const tailBudget = budget - headBudget;
    let head = '';
    let headWidth = 0;
    for (const char of value) {
        const w = codePointWidth(char.codePointAt(0), ambiguousWide);
        if (headWidth + w > headBudget)
            break;
        head += char;
        headWidth += w;
    }
    let tail = '';
    let tailWidth = 0;
    const chars = [...value];
    for (let i = chars.length - 1; i >= 0; i--) {
        const char = chars[i];
        const w = codePointWidth(char.codePointAt(0), ambiguousWide);
        if (tailWidth + w > tailBudget)
            break;
        tail = `${char}${tail}`;
        tailWidth += w;
    }
    return `${head}${ellipsis}${tail}`;
}
/**
 * Pad a glyph so active/idle variants share one column width.
 * @param {string} glyph
 * @param {string[]} variants
 * @param {WidthOptions} [options]
 */
export function alignGlyph(glyph, variants, options = {}) {
    const width = Math.max(0, ...variants.map((item) => stringWidth(item, options)));
    return padEndWidth(glyph, width, options);
}
/** Cursor used by ↑↓ menus (U+279C ➜). */
export const MENU_CHECK = '➜';
export const MENU_CHECK_IDLE = ' ';
/**
 * Align menu cursor chrome so active/idle share one display column.
 * Ghostty draws ➜ as 1 cell (unlike ✓); pad idle as narrow.
 * @param {boolean} active
 */
export function alignMenuCheck(active) {
    return alignGlyph(active ? MENU_CHECK : MENU_CHECK_IDLE, [MENU_CHECK, MENU_CHECK_IDLE], { ambiguousWide: false });
}
