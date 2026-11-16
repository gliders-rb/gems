import { ExpressiveCodeTheme, definePlugin, addClassName } from '@astrojs/starlight/expressive-code';
import { palettes, thermalTheme } from './src/config/thermal.mjs';

const dark = new ExpressiveCodeTheme(thermalTheme('thermal-dark', 'dark', palettes.dark));
const light = new ExpressiveCodeTheme(thermalTheme('thermal-light', 'light', palettes.light));

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
