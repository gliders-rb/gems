// Specs for the hero generator (src/hero/hero.mjs). Run with `npm run test:hero`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseStoryboard, checkStoryboard, timeline, stateAt, steps, stepStates, render } from '../src/hero/hero.mjs';

const source = readFileSync(fileURLToPath(new URL('../src/hero/storyboard.md', import.meta.url)), 'utf8');

// A tiny storyboard in its own domain (a lighthouse log), so the specs don't lean on the real one.
const tiny = (overrides = {}) => {
  const front = {
    title: 'Lamp log',
    message: 'm',
    code: 'lamp.rb',
    calls: 'calls.rb',
    fade: 0.2,
    beats: [
      { id: 'start', at: 0, caption: 'A lamp.' },
      { id: 'lit', at: 1, run: 'lit', show: ['message'], steps: ['trim', 'light'], caption: 'Lit.', marks: [] },
      { id: 'end', at: 3, caption: 'Done.' },
    ],
    ...overrides,
  };
  return [
    '---',
    JSON.stringify(front),
    '---',
    '',
    '## start: Start',
    '',
    'Some words.',
    '',
    '```ruby run title="lamp.rb"',
    'class LightLamp < Actionable::Action',
    '  step :trim',
    '  step :light',
    'end',
    '```',
    '',
    '```ruby run title="calls.rb"',
    'lit = LightLamp.run',
    'lit.status    # => :success',
    'lit.message   # => "on"',
    '```',
    '',
    '```ruby run',
    'lit.history.steps.map(&:name)   # => [:trim, :light]',
    '```',
    '',
  ].join('\n');
};

test('the real storyboard passes every check', () => {
  assert.deepEqual(checkStoryboard(parseStoryboard(source)), []);
});

test('a run beat takes its call, badge and detail from the asserted lines', () => {
  const sb = parseStoryboard(tiny());
  assert.deepEqual(checkStoryboard(sb), []);
  const run = sb.runs.lit;
  assert.equal(run.call, 'LightLamp.run');
  assert.equal(run.status, 'success');
  assert.deepEqual(run.details, ['"on"']);
});

test('a detail with no assertion behind it is refused', () => {
  const sb = parseStoryboard(tiny({ beats: [
    { id: 'start', at: 0, caption: 'A lamp.' },
    { id: 'lit', at: 1, run: 'lit', show: ['code'], steps: ['trim', 'light'], caption: 'Lit.' },
    { id: 'end', at: 3, caption: 'Done.' },
  ] }));
  assert.match(checkStoryboard(sb).join('\n'), /lit\.code/);
});

test('steps that disagree with the asserted history are refused', () => {
  const sb = parseStoryboard(tiny({ beats: [
    { id: 'start', at: 0, caption: 'A lamp.' },
    { id: 'lit', at: 1, run: 'lit', show: ['message'], steps: ['trim'], caption: 'Lit.' },
    { id: 'end', at: 3, caption: 'Done.' },
  ] }));
  assert.match(checkStoryboard(sb).join('\n'), /steps/);
});

test('a mark needs a proof line that is a checked assertion', () => {
  const marks = [{ line: 'step :trim', kind: 'ok', tag: 'trimmed', proof: 'lit.wick   # => :short' }];
  const sb = parseStoryboard(tiny({ beats: [
    { id: 'start', at: 0, caption: 'A lamp.' },
    { id: 'lit', at: 1, run: 'lit', show: ['message'], steps: ['trim', 'light'], caption: 'Lit.', marks },
    { id: 'end', at: 3, caption: 'Done.' },
  ] }));
  assert.match(checkStoryboard(sb).join('\n'), /proof/);
});

test('a mark must name exactly one code line', () => {
  const marks = [{ line: 'step :', kind: 'ok', tag: 'x', proof: 'lit.status    # => :success' }];
  const sb = parseStoryboard(tiny({ beats: [
    { id: 'start', at: 0, caption: 'A lamp.' },
    { id: 'lit', at: 1, run: 'lit', show: ['message'], steps: ['trim', 'light'], caption: 'Lit.', marks },
    { id: 'end', at: 3, caption: 'Done.' },
  ] }));
  assert.match(checkStoryboard(sb).join('\n'), /matches 2 lines/);
});

test('the timeline ends on the final frame: results shown, marks and passing captions hidden', () => {
  const sb = parseStoryboard(source);
  const tl = timeline(sb);
  const end = tl.duration;
  for (const el of tl.elements) {
    const final = el.kind === 'result' || el.kind === 'call' || (el.kind === 'caption' && el.final);
    // a veil dims a call until its beat, so none is left at the end
    assert.equal(stateAt(el, end, tl.fade), final ? 1 : 0, `${el.id} at the end`);
    assert.equal(el.finalVisible, final, `${el.id} base state`);
  }
});

test('at the start the code, every call (veiled) and the first caption are on screen, and no result', () => {
  const tl = timeline(parseStoryboard(source));
  for (const el of tl.elements) {
    const first = (el.kind === 'caption' && el.beat === 'setup') || el.kind === 'call' || el.kind === 'veil';
    assert.equal(stateAt(el, 0, tl.fade), first ? 1 : 0, el.id);
  }
});

test('each run shows its result before the next beat starts', () => {
  const sb = parseStoryboard(source);
  const tl = timeline(sb);
  for (const el of tl.elements.filter((e) => e.kind === 'result')) {
    const beat = sb.front.beats.findIndex((b) => b.id === el.beat);
    const next = sb.front.beats[beat + 1].at;
    assert.equal(stateAt(el, next - 0.01, tl.fade), 1, `${el.id} by ${next}`);
  }
});

// ---- the stepper: one step per beat ----

test('each beat is one numbered step, in order, lasting until the next beat starts', () => {
  const sb = parseStoryboard(tiny());
  assert.deepEqual(
    steps(sb).map((s) => [s.n, s.id, s.caption, s.dwell]),
    [
      [1, 'start', 'A lamp.', 1],
      [2, 'lit', 'Lit.', 2],
      [3, 'end', 'Done.', null],
    ],
  );
});

test('the last step is the final frame: every element as the static figure shows it', () => {
  const sb = parseStoryboard(source);
  const tl = timeline(sb);
  const last = stepStates(sb, tl).at(-1);
  for (const el of tl.elements) assert.equal(last[el.id].opacity, el.finalVisible ? 1 : 0, el.id);
});

test('a step shows the calls and results so far, and only its own marks', () => {
  const sb = parseStoryboard(source);
  const tl = timeline(sb);
  const states = stepStates(sb, tl);
  const order = sb.front.beats.map((b) => b.id);
  states.forEach((state, k) => {
    for (const el of tl.elements) {
      const from = order.indexOf(el.beat);
      // Marks, the active-call bar and captions belong to their own step; results stay once shown; every call is
      // always there, veiled until its own step, so no step shows an empty calls pane.
      const want = {
        mark: from === k,
        active: from === k,
        caption: from === k,
        result: from <= k,
        call: true,
        veil: from > k,
      }[el.kind];
      assert.equal(state[el.id].opacity, want ? 1 : 0, `step ${k + 1}, ${el.id} (${el.kind} of ${el.beat})`);
    }
  });
});

test('an element entering in a step waits for its place in that beat; others change at once', () => {
  const sb = parseStoryboard(source);
  const tl = timeline(sb);
  const all = steps(sb);
  stepStates(sb, tl).forEach((state, k) => {
    const step = all[k];
    for (const el of tl.elements) {
      const { delay } = state[el.id];
      const entering = el.spans.some(([on]) => on > step.at && on < step.at + (step.dwell ?? Infinity));
      if (entering && state[el.id].opacity === 1) {
        assert.ok(delay > 0 && delay < (step.dwell ?? Infinity), `${el.id} in step ${k + 1}: ${delay}`);
      } else {
        assert.equal(delay, 0, `${el.id} in step ${k + 1}`);
      }
    }
  });
});

test('the figure carries its step controls hidden, so readers without scripts get no dead buttons', () => {
  const sb = parseStoryboard(source);
  const fake = { codeToTokens: (code) => ({ tokens: code.split('\n').map((l) => [{ content: l }]) }) };
  const { html, css } = render(sb, fake);
  const n = sb.front.beats.length;
  assert.match(html, /<div class="hx-steps"[^>]*\bhidden\b/);
  assert.equal((html.match(/class="hx-step"/g) ?? []).length, n);
  assert.match(html, /data-dwell="[\d.,]+"/);
  assert.doesNotMatch(css, /@keyframes/);
  assert.match(css, /\.hx\[data-step="1"\]/);
  assert.doesNotMatch(css, new RegExp(`\\.hx\\[data-step="${n}"\\] [^{]*\\{opacity`), 'the last step shows the final frame as is');
});

test('a leaving caption goes at once, so two captions never overlap in their shared cell', () => {
  const sb = parseStoryboard(source);
  const fake = { codeToTokens: (code) => ({ tokens: code.split('\n').map((l) => [{ content: l }]) }) };
  const { css } = render(sb, fake);
  const tl = timeline(sb);
  const motion = css.slice(css.indexOf('@media (prefers-reduced-motion: no-preference)'));
  stepStates(sb, tl).forEach((state, k) => {
    for (const el of tl.elements.filter((e) => e.kind === 'caption' && state[e.id].opacity === 0)) {
      assert.ok(motion.includes(`.hx[data-step="${k + 1}"] .hx-${el.id}{transition:none}`), `step ${k + 1}, ${el.id}`);
    }
  });
});
