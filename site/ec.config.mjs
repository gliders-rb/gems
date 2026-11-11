import { ExpressiveCodeTheme, definePlugin, addClassName } from '@astrojs/starlight/expressive-code';

/** Builds a code theme from nine colours. */
function garnetTheme(name, type, c) {
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

const dark = garnetTheme('garnet-dark', 'dark', {
  background: '#151a2c',
  foreground: '#d5daeb',
  keyword: '#ff7d98',
  constant: '#ffc978',
  symbol: '#6fd6c4',
  string: '#9cc3e6',
  number: '#ffb547',
  method: '#c4b4ff',
  comment: '#8c95b0',
});

const light = garnetTheme('garnet-light', 'light', {
  background: '#f2f4fb',
  foreground: '#1b2033',
  keyword: '#a8133a',
  constant: '#8a4a00',
  symbol: '#0b6b61',
  string: '#2b5f8a',
  number: '#954b00',
  method: '#5a3db3',
  comment: '#5d6479',
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
