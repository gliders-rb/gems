// The Node half of the differential check (JS-B91): every translated pattern must compile under the `u` flag and
// agree with Ruby on every sample. Reads the report from results.rb on stdin; exits 1 on any problem.
import { readFileSync } from 'node:fs';

// A pattern_for that gave up on everything would otherwise pass: fail below this many translated patterns
// (about 85% of what the corpus translates today).
const MIN_TRANSLATED = Number(process.env.MIN_TRANSLATED ?? 0);

const report = JSON.parse(readFileSync(0, 'utf8'));
const problems = [];
let translated = 0;
let compared = 0;
let untranslated = 0;
let rejected = 0;

for (const entry of report.cases) {
  const label = `/${entry.source}/${entry.flags}`;
  if (entry.status === 'ruby-rejects') { rejected += 1; continue; }
  if (entry.status === 'untranslated') { untranslated += 1; continue; }
  translated += 1;
  let regexp;
  try {
    regexp = new RegExp(entry.pattern, 'u');
  } catch (error) {
    problems.push(`${label} -> ${JSON.stringify(entry.pattern)}: does not compile under u: ${error.message}`);
    continue;
  }
  for (const [sample, rubyMatches] of entry.samples) {
    compared += 1;
    const nodeMatches = regexp.test(sample);
    if (nodeMatches !== rubyMatches) {
      problems.push(`${label} -> ${JSON.stringify(entry.pattern)} on ${JSON.stringify(sample)}: Ruby ${rubyMatches}, Node ${nodeMatches}`);
    }
  }
}

if (translated < MIN_TRANSLATED) {
  problems.push(`only ${translated} patterns translated, the floor is ${MIN_TRANSLATED}`);
}
for (const line of problems) console.log(line);
console.log(`Ruby ${report.ruby}, Node ${process.versions.node}: ${report.cases.length} Regexps, ${translated} translated ` +
  `(${compared} samples compared), ${untranslated} left untranslated, ${rejected} rejected by Ruby; ${problems.length} problem(s)`);
process.exit(problems.length === 0 ? 0 : 1);
