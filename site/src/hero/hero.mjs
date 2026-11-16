// The hero generator's core: reads the storyboard, checks every claim against its asserted Ruby, lays out the
// timeline and renders the animation as static HTML and CSS. bin/hero drives it; test/hero.test.mjs specs it.
//
// The rendered figure IS the final frame, which is also the last step. Each storyboard beat is one step of a stepper:
// a script sets data-step="n" on the figure and the generated CSS shows that step, with the beat's marks entering in
// order through transition delays. With scripts off, readers get the finished picture and no controls.
import { parse as parseYaml } from 'yaml';

const FENCE = /^(`{3,})(\w*)\s*(.*)$/;
const ARROW = /^(?<expr>.*?\S)\s+#\s*=>\s?(?<value>.*)$/;
const squash = (s) => s.trim().replace(/\s+/g, ' ');

/**
 * Splits a storyboard Markdown file into its front matter, Ruby fences and prose sections.
 * @param {string} text
 */
export function parseStoryboard(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error('storyboard: no front matter');
  const front = parseYaml(match[1]);
  const lines = match[2].split('\n');
  const fences = [];
  const sections = [];
  let open = null;
  let section = null;
  for (const line of lines) {
    if (open) {
      if (line.startsWith(open.ticks) && line.trim() === open.ticks) {
        fences.push(open);
        open = null;
      } else {
        open.lines.push(line);
      }
      continue;
    }
    const fence = line.match(FENCE);
    if (fence) {
      const meta = fence[3];
      open = {
        ticks: fence[1],
        lang: fence[2],
        run: fence[2] === 'ruby' && /\brun\b/.test(meta),
        title: meta.match(/title="([^"]+)"/)?.[1] ?? null,
        lines: [],
      };
      continue;
    }
    const heading = line.match(/^## (\w+): (.+)$/) || line.match(/^## (\w+)$/);
    if (heading) {
      section = { id: heading[1], title: heading[2] ?? heading[1], text: [] };
      sections.push(section);
    } else if (section) {
      section.text.push(line);
    }
  }
  for (const s of sections) {
    s.paragraphs = s.text.join('\n').split(/\n\s*\n/).map((p) => squash(p)).filter(Boolean);
    delete s.text;
  }
  const runnable = fences.filter((f) => f.run);
  const asserted = new Map();
  for (const fence of runnable) {
    for (const line of fence.lines) {
      const a = line.match(ARROW);
      if (a) asserted.set(squash(a.groups.expr), a.groups.value.trim());
    }
  }
  const sb = { front, fences, sections, asserted, runs: {} };
  sb.codeFence = runnable.find((f) => f.title === front.code) ?? null;
  sb.callsFence = runnable.find((f) => f.title === front.calls) ?? null;
  for (const beat of front.beats ?? []) {
    if (!beat.run) continue;
    const name = beat.run;
    const callLine = sb.callsFence?.lines.find((l) => l.startsWith(`${name} = `));
    sb.runs[name] = {
      name,
      call: callLine ? callLine.slice(name.length + 3).trim() : null,
      status: (asserted.get(`${name}.status`) ?? '').replace(/^:/, '') || null,
      details: (beat.show ?? []).map((expr) => asserted.get(`${name}.${expr}`) ?? null),
    };
  }
  return sb;
}

const codeLines = (sb) => sb.codeFence?.lines ?? [];

/** Index of the one code line containing `needle`, or an error message. */
function findLine(sb, needle) {
  const hits = codeLines(sb).flatMap((l, i) => (l.includes(needle) ? [i] : []));
  if (hits.length === 1) return hits[0];
  return `"${needle}" matches ${hits.length} lines of ${sb.front.code}`;
}

const stepLine = (sb, name) => findLine(sb, `step :${name}`);
const declaredSteps = (sb) => codeLines(sb).flatMap((l) => l.match(/^\s*step :(\w+)/)?.[1] ?? []);

/**
 * Every way the storyboard claims something its Ruby does not assert. Empty means it is safe to render.
 * @returns {string[]}
 */
export function checkStoryboard(sb) {
  const errors = [];
  const { front } = sb;
  if (!sb.codeFence) errors.push(`no runnable fence titled "${front.code}"`);
  if (!sb.callsFence) errors.push(`no runnable fence titled "${front.calls}"`);
  const beats = front.beats ?? [];
  if (beats.length < 2) errors.push('a storyboard needs at least two beats');
  beats.forEach((beat, i) => {
    if (typeof beat.at !== 'number') errors.push(`beat ${beat.id}: at must be a number of seconds`);
    if (i > 0 && !(beat.at > beats[i - 1].at)) errors.push(`beat ${beat.id}: starts before the beat above it`);
    if (!beat.caption) errors.push(`beat ${beat.id}: no caption`);
  });
  if (beats.at(-1)?.run) errors.push('the last beat is the final frame and cannot play a run');
  for (const beat of beats.filter((b) => b.run)) {
    const run = sb.runs[beat.run];
    const where = `beat ${beat.id}`;
    if (!run.call) errors.push(`${where}: no "${beat.run} = ..." line in ${front.calls}`);
    if (!['success', 'failure', 'skipped'].includes(run.status)) {
      errors.push(`${where}: ${beat.run}.status has no # => :success, :failure or :skipped`);
    }
    (beat.show ?? []).forEach((expr, i) => {
      if (run.details[i] === null) errors.push(`${where}: ${beat.run}.${expr} has no # => assertion`);
    });
    const steps = beat.steps ?? [];
    const wanted = `[${steps.map((s) => `:${s}`).join(', ')}]`;
    const history = sb.asserted.get(`${beat.run}.history.steps.map(&:name)`) ?? sb.asserted.get(`${beat.run}.history`);
    if (history === undefined) errors.push(`${where}: steps need an asserted ${beat.run}.history.steps.map(&:name)`);
    else if (squash(history) !== wanted) errors.push(`${where}: steps ${wanted} but the history asserts ${history}`);
    for (const name of declaredSteps(sb).length ? declaredSteps(sb) : []) {
      const at = stepLine(sb, name);
      if (typeof at === 'string') errors.push(`${where}: ${at}`);
    }
    for (const s of steps) {
      if (!declaredSteps(sb).includes(s)) errors.push(`${where}: step :${s} is not declared in ${front.code}`);
    }
    for (const mark of beat.marks ?? []) {
      const at = findLine(sb, mark.line);
      if (typeof at === 'string') errors.push(`${where}: mark ${at}`);
      if (!['ok', 'stop', 'skip'].includes(mark.kind)) errors.push(`${where}: mark kind must be ok, stop or skip`);
      const proof = mark.proof?.match(ARROW);
      if (!proof) errors.push(`${where}: mark "${mark.tag}" needs a proof of the form "expr # => value"`);
      else if (sb.asserted.get(squash(proof.groups.expr)) !== proof.groups.value.trim()) {
        errors.push(`${where}: proof "${mark.proof}" is not an assertion in a runnable fence`);
      }
    }
  }
  return errors;
}

/**
 * Lays out every animated element as a list of visible spans [on, off) in seconds (off null: stays on).
 * A run beat lifts the veil off its call, marks the input fields, walks the steps one by one, then shows its result.
 */
export function timeline(sb) {
  const { front } = sb;
  const beats = front.beats;
  const fade = front.fade ?? 0.25;
  const duration = beats.at(-1).at + 1;
  const elements = [];
  const add = (el) => {
    el.id = `a${elements.length + 1}`;
    el.finalVisible = el.spans.some(([, off]) => off === null);
    elements.push(el);
    return el;
  };
  beats.forEach((beat, i) => {
    const end = beats[i + 1]?.at ?? null;
    add({ kind: 'caption', beat: beat.id, text: beat.caption, final: end === null, spans: [[beat.at, end]] });
    if (!beat.run) return;
    const run = sb.runs[beat.run];
    const steps = beat.steps ?? [];
    const marks = beat.marks ?? [];
    const isField = (m) => /^\s*(required|optional) /.test(codeLines(sb)[findLine(sb, m.line)]);
    let t = beat.at + 0.5;
    // Every call is on screen from the start, veiled (dimmed) until its own beat, so no step shows an empty pane.
    add({ kind: 'call', beat: beat.id, run: run.name, spans: [[0, null]] });
    add({ kind: 'veil', beat: beat.id, run: run.name, spans: [[0, beat.at]] });
    add({ kind: 'active', beat: beat.id, run: run.name, spans: [[beat.at, end]] });
    for (const mark of marks.filter(isField)) {
      add({ kind: 'mark', beat: beat.id, line: findLine(sb, mark.line), tone: mark.kind, tag: mark.tag, spans: [[t, end]] });
    }
    t += 0.4;
    const stopped = run.status === 'failure' && steps.length ? steps.at(-1) : null;
    for (const name of declaredSteps(sb)) {
      const ran = steps.includes(name);
      const tone = !ran ? 'skip' : name === stopped ? 'stop' : 'ok';
      const tag = !ran ? 'not run' : name === stopped ? 'stopped' : 'ran';
      add({ kind: 'mark', beat: beat.id, line: stepLine(sb, name), tone, tag, spans: [[t, end]] });
      if (name === stopped) {
        for (const mark of marks.filter((m) => !isField(m))) {
          add({ kind: 'mark', beat: beat.id, line: findLine(sb, mark.line), tone: mark.kind, tag: mark.tag, spans: [[t + 0.3, end]] });
        }
      }
      t += 0.45;
    }
    add({ kind: 'result', beat: beat.id, run: run.name, spans: [[Math.min(t + 0.05, end - 1), null]] });
  });
  return { duration, fade, elements };
}

const round3 = (n) => Math.round(n * 1000) / 1000;

/**
 * The stepper's steps: one per beat, in order. `dwell` is how long autoplay stays on it (until the next beat
 * starts); the last step's is null, since the player decides how long to hold the final frame.
 */
export function steps(sb) {
  const beats = sb.front.beats;
  return beats.map((b, i) => ({
    n: i + 1,
    id: b.id,
    caption: b.caption,
    at: b.at,
    dwell: i + 1 < beats.length ? round3(beats[i + 1].at - b.at) : null,
  }));
}

const visibleAt = (el, t) => el.spans.some(([on, off]) => on <= t && (off === null || t < off));

/**
 * What each step shows: for every element, its opacity once the step has played out (0 or 1), and how long after
 * the step starts it enters (0 unless it enters part-way through the beat).
 * @returns {Array<Record<string, {opacity: number, delay: number}>>}
 */
export function stepStates(sb, tl = timeline(sb)) {
  return steps(sb).map((step) => {
    const settled = step.dwell === null ? tl.duration : step.at + step.dwell - 0.001;
    const state = {};
    for (const el of tl.elements) {
      const opacity = visibleAt(el, settled) ? 1 : 0;
      const entry = el.spans.find(([on]) => on > step.at && on <= settled);
      state[el.id] = { opacity, delay: opacity && entry ? round3(entry[0] - step.at) : 0 };
    }
    return state;
  });
}

/** Opacity (0 or 1, or between while fading) of an element at time t. */
export function stateAt(el, t, fade) {
  let v = 0;
  for (const [on, off] of el.spans) {
    if (t < on) continue;
    const rise = on === 0 ? 1 : Math.min(1, (t - on) / fade);
    if (off === null || t < off) v = Math.max(v, rise);
    else v = Math.max(v, Math.max(0, 1 - (t - off) / fade));
  }
  return Math.round(v * 1000) / 1000;
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/**
 * One highlighted Ruby line as HTML. Each distinct (dark, light) colour pair becomes a short class (t0, t1 ...),
 * collected in `colours` so the CSS can give each class its colour in both schemes.
 */
function tokensHtml(tokens, colours) {
  return tokens
    .map((tok) => {
      const st = tok.htmlStyle ?? {};
      const key = `${st['--shiki-dark'] ?? ''}|${st['--shiki-light'] ?? ''}`;
      if (key === '|') return esc(tok.content);
      if (!colours.has(key)) colours.set(key, `t${colours.size}`);
      return `<span class="${colours.get(key)}">${esc(tok.content)}</span>`;
    })
    .join('');
}

const highlight = (hl, code) =>
  hl.codeToTokens(code, { lang: 'ruby', themes: { dark: 'thermal-dark', light: 'thermal-light' }, defaultColor: false }).tokens;

/**
 * The figure (HTML) and its timeline CSS. `hl` is a Shiki highlighter loaded with both thermal themes and Ruby.
 * @returns {{html: string, css: string}}
 */
export function render(sb, hl) {
  const tl = timeline(sb);
  const colours = new Map();
  const { front } = sb;
  const byLine = new Map();
  for (const el of tl.elements.filter((e) => e.kind === 'mark')) {
    if (!byLine.has(el.line)) byLine.set(el.line, []);
    byLine.get(el.line).push(el);
  }
  const code = highlight(hl, codeLines(sb).join('\n'))
    .map((tokens, i) => {
      const marks = byLine.get(i) ?? [];
      const hls = marks.map((m) => `<span class="hx-hl hx-anim hx-${m.id} ${m.tone}" aria-hidden="true"></span>`).join('');
      const tags = marks.map((m) => `<span class="hx-tag hx-anim hx-${m.id} ${m.tone}" aria-hidden="true">${esc(m.tag)}</span>`).join('');
      return `<span class="hx-line">${hls}<span class="hx-src">${tokensHtml(tokens, colours) || ' '}</span>${tags}</span>`;
    })
    .join(''); // block lines: a newline between them would print as a blank line inside <pre>
  const runs = front.beats
    .filter((b) => b.run)
    .map((beat) => {
      const run = sb.runs[beat.run];
      const el = (kind) => tl.elements.find((e) => e.kind === kind && e.beat === beat.id);
      const call = tokensHtml(highlight(hl, run.call)[0], colours);
      const details = run.details.map((d) => `<code class="hx-value">${tokensHtml(highlight(hl, d)[0], colours)}</code>`).join(' ');
      return [
        `<li class="hx-run">`,
        `<span class="hx-active hx-anim hx-${el('active').id}" aria-hidden="true"></span>`,
        `<span class="hx-veil hx-anim hx-${el('veil').id}" aria-hidden="true"></span>`,
        `<code class="hx-call hx-anim hx-${el('call').id}">${call}</code>`,
        `<p class="hx-result hx-anim hx-${el('result').id}"><span class="af-badge ${run.status}">${run.status}</span> ${details}</p>`,
        `</li>`,
      ].join('');
    })
    .join('\n');
  const all = steps(sb);
  const stepOf = (beatId) => all.find((st) => st.id === beatId).n;
  const captions = tl.elements
    .filter((e) => e.kind === 'caption')
    .map((c) => {
      const hidden = c.final ? '' : ' aria-hidden="true"';
      return `<span class="hx-cap hx-anim hx-${c.id}${c.final ? ' final' : ''}" data-cap="${stepOf(c.beat)}"${hidden}>${captionHtml(c.text)}</span>`;
    })
    .join('');
  // The stepper's controls ship hidden: the script shows them, so readers without scripts get no dead buttons.
  const numbers = all
    .map((st) => `<li><button type="button" class="hx-step" data-to="${st.n}" aria-label="Step ${st.n} of ${all.length}">${st.n}</button></li>`)
    .join('');
  const controls = [
    `<div class="hx-steps" role="group" aria-label="Steps of the example" hidden>`,
    `<button type="button" class="hx-prev" aria-label="Previous step">‹</button>`,
    `<ol class="hx-numbers">${numbers}</ol>`,
    `<button type="button" class="hx-next" aria-label="Next step">›</button>`,
    `<button type="button" class="hx-play" aria-label="Pause autoplay"><span class="hx-icon" aria-hidden="true"></span></button>`,
    `</div>`,
  ].join('');
  const dwell = all.filter((st) => st.dwell !== null).map((st) => st.dwell).join(',');
  const html = [
    `<figure class="hx" data-hx data-steps="${all.length}" data-dwell="${dwell}">`,
    `<div class="hx-window">`,
    `<div class="hx-pane hx-code"><div class="hx-bar"><span class="hx-file">${esc(front.code)}</span></div>`,
    `<pre class="hx-pre"><code>${code}</code></pre></div>`,
    `<div class="hx-pane hx-calls"><div class="hx-bar"><span class="hx-file">${esc(front.calls)}</span></div>`,
    `<ol class="hx-runs">\n${runs}\n</ol></div>`,
    `</div>`,
    controls,
    `<figcaption class="hx-captions">${captions}</figcaption>`,
    `<p class="hx-live" aria-live="polite"></p>`,
    `</figure>`,
  ].join('\n');
  return { html: `${html}\n`, css: stepCss(sb, tl) + colourCss(colours) };
}

/** Token colours for both schemes: dark is the default, as on the rest of the site. */
function colourCss(colours) {
  const rules = [];
  for (const [key, cls] of colours) {
    const [dark, light] = key.split('|');
    rules.push(`.hx .${cls}{color:${dark.toLowerCase()}}`, `:root[data-theme='light'] .hx .${cls}{color:${light.toLowerCase()}}`);
  }
  return `${rules.join('\n')}\n`;
}

/** Captions are plain text; `backticks` mark code, as in Markdown. */
function captionHtml(text) {
  return esc(text).replace(/`([^`]+)`/g, '<code>$1</code>');
}

/**
 * The generated CSS. The base state is the final frame. data-step="n" shows step n: only the elements that differ
 * from the final frame need a rule, so the last step has none. Transitions run only when the reader hasn't asked
 * for less motion; an element entering part-way through a beat waits for its moment with a transition delay.
 */
function stepCss(sb, tl) {
  const out = ['/* Generated by bin/hero from src/hero/storyboard.md. Do not edit by hand. */'];
  for (const el of tl.elements) {
    if (!el.finalVisible) out.push(`.hx .hx-${el.id}{opacity:0}`);
  }
  const rises = (el) => el.kind === 'call' || el.kind === 'result';
  const delays = [];
  stepStates(sb, tl).forEach((state, k) => {
    for (const el of tl.elements) {
      const { opacity, delay } = state[el.id];
      const sel = `.hx[data-step="${k + 1}"] .hx-${el.id}`;
      if (opacity !== (el.finalVisible ? 1 : 0)) out.push(`${sel}{opacity:${opacity}${!opacity && rises(el) ? ';translate:0 0.3rem' : ''}}`);
      if (delay) delays.push(`${sel}{transition-delay:${delay}s}`);
      // Captions share one cell: the leaving one goes at once, so it never shows through the arriving one.
      if (el.kind === 'caption' && !opacity) delays.push(`${sel}{transition:none}`);
    }
  });
  out.push('@media (prefers-reduced-motion: no-preference){');
  out.push(`.hx[data-step] .hx-anim{transition:opacity ${tl.fade}s linear,translate ${tl.fade}s ease-out}`);
  out.push(...delays);
  out.push('}');
  return `${out.join('\n')}\n`;
}
