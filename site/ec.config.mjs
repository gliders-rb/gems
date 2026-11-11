import { ExpressiveCodeTheme, definePlugin, addClassName } from '@astrojs/starlight/expressive-code';

/** Builds a code theme from nine colours. */
function thermalTheme(name, type, c) {
  const rule = (scope, foreground, fontStyle) => ({
    scope,
    settings: { foreground, ...(fontStyle ? { fontStyle } : {}) },
  });
  return new ExpressiveCodeTheme({
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
  });
}

const dark = thermalTheme('thermal-dark', 'dark', {
  background: '#100e0c',
  foreground: '#ddd6ca',
  keyword: '#8fb0d6',
  constant: '#d8c3a0',
  symbol: '#c4a6cf',
  string: '#a9c08f',
  number: '#d4b483',
  method: '#cdbfae',
  comment: '#8a8174',
});

const light = thermalTheme('thermal-light', 'light', {
  background: '#f2eee7',
  foreground: '#1a1612',
  keyword: '#2f5f8f',
  constant: '#7a4f12',
  symbol: '#6b4c9a',
  string: '#4d6b2f',
  number: '#7a4f12',
  method: '#4a433b',
  comment: '#6b6358',
});

/** Marks any span that starts with `# =>` so the theme sheet can style it as a result (SI-B9). */
function resultPlugin() {
  return definePlugin({
    name: 'af-result',
    hooks: {
      postprocessRenderedLine: ({ renderData }) => {
        const walk = (node) => {
          if (!node.children) return;
          for (const child of node.children) {
            if (child.type === 'element' && child.tagName === 'span') {
              const first = child.children?.[0];
              if (first?.type === 'text' && first.value.trimStart().startsWith('# =>')) {
                addClassName(child, 'af-result');
                continue;
              }
            }
            walk(child);
          }
        };
        walk(renderData.lineAst);
      },
    },
  });
}

export default {
  themes: [dark, light],
  plugins: [resultPlugin()],
  styleOverrides: {
    borderRadius: '0.375rem',
    codeFontSize: '0.875rem',
    codeFontFamily: 'var(--af-font-code)',
  },
};
