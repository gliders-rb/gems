// The two code palettes ("thermal-dark", "thermal-light") and the scope rules that colour Ruby with them.
// ec.config.mjs builds the Expressive Code themes from these, and bin/hero builds the landing animation's
// highlighter from the same values, so code in the animation matches every code block on the site.

/** Nine colours per scheme: background, foreground and seven token groups. */
export const palettes = {
  dark: {
    background: '#100e0c',
    foreground: '#ddd6ca',
    keyword: '#8fb0d6',
    constant: '#d8c3a0',
    symbol: '#c4a6cf',
    string: '#a9c08f',
    number: '#d4b483',
    method: '#cdbfae',
    comment: '#8a8174',
  },
  light: {
    background: '#f2eee7',
    foreground: '#1a1612',
    keyword: '#2f5f8f',
    constant: '#7a4f12',
    symbol: '#6b4c9a',
    string: '#4d6b2f',
    number: '#7a4f12',
    method: '#4a433b',
    comment: '#6b6358',
  },
};

/**
 * A TextMate theme (name, type, colors, settings) for one palette.
 * @param {string} name
 * @param {'dark'|'light'} type
 * @param {Record<string, string>} c one entry of `palettes`
 */
export function thermalTheme(name, type, c) {
  const rule = (scope, foreground, fontStyle) => ({
    scope,
    settings: { foreground, ...(fontStyle ? { fontStyle } : {}) },
  });
  return {
    name,
    type,
    colors: {
      'editor.background': c.background,
      'editor.foreground': c.foreground,
    },
    settings: [
      rule(['keyword', 'storage', 'keyword.operator', 'storage.type', 'storage.modifier'], c.keyword),
      rule(['entity.name.type', 'entity.name.class', 'support.class', 'support.type', 'entity.other.inherited-class', 'variable.other.constant'], c.constant),
      rule(['constant.other.symbol', 'string.other.symbol', 'punctuation.definition.constant', 'constant.other.symbol.hashkey'], c.symbol),
      rule(['string', 'punctuation.definition.string', 'string.regexp'], c.string),
      rule(['constant.numeric', 'constant.language', 'constant.character'], c.number),
      rule(['entity.name.function', 'support.function', 'meta.function-call', 'variable.function'], c.method),
      rule(['comment', 'punctuation.definition.comment'], c.comment, 'italic'),
    ],
  };
}
