// sync-content.mjs: copy the repo's own markdown into the docs before every build.
//
// THE DOCS ARE THE SPEC. Every page under spec/, adr/, PRINCIPLES.md and docs/adopting.md is
// copied in (the copies are gitignored), so a page here cannot say something the repo does
// not. Each file's first `# ` heading becomes the page title. Links are rewritten: one to
// another synced file becomes its route on this site, and one to anything else in the repo
// becomes its GitHub URL, so nothing dangles. The options page is rendered by
// scripts/options-page.sh from factory/options.tsv, and install.sh is served at /install.sh.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, copyFileSync } from 'node:fs';
import { dirname, join, resolve, posix } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SITE = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = resolve(SITE, '..');
const DOCS = join(SITE, 'src/content/docs');
const GITHUB = 'https://github.com/xodeeq/xal-factory/blob/main/';

// repo path -> site route (without slashes). Only these are pages; everything else links out.
const pages = new Map();
for (const f of readdirSync(join(ROOT, 'spec')).filter((f) => f.endsWith('.md'))) {
  pages.set(`spec/${f}`, f === 'README.md' ? 'spec' : `spec/${f.replace(/\.md$/, '')}`);
}
for (const f of readdirSync(join(ROOT, 'adr')).filter((f) => /^\d{4}-.*\.md$/.test(f))) {
  pages.set(`adr/${f}`, `adr/${f.replace(/\.md$/, '')}`);
}
pages.set('adr/README.md', 'adr');
pages.set('PRINCIPLES.md', 'principles');
pages.set('docs/adopting.md', 'adopting');

function rewriteLinks(body, srcPath) {
  return body.replace(/\]\(([^)\s]+)(\s+"[^"]*")?\)/g, (m, target, title = '') => {
    if (/^(https?:|mailto:|#)/.test(target)) {
      // An absolute link into this repo that names a synced page becomes that page.
      const gh = target.match(/^https:\/\/github\.com\/xodeeq\/xal-factory\/blob\/main\/([^#]+)(#.*)?$/);
      if (gh && pages.has(gh[1])) return `](/${pages.get(gh[1])}/${gh[2] ?? ''}${title})`;
      return m;
    }
    const [path, anchor = ''] = target.split('#');
    const repoPath = posix.normalize(posix.join(posix.dirname(srcPath), path));
    const hash = anchor ? `#${anchor}` : '';
    if (pages.has(repoPath)) return `](/${pages.get(repoPath)}/${hash}${title})`;
    // A vendored sibling: spec files link to each other by bare name.
    if (srcPath.startsWith('spec/') && pages.has(`spec/${path}`)) return `](/${pages.get(`spec/${path}`)}/${hash}${title})`;
    return `](${GITHUB}${repoPath.replace(/\/$/, '')}${hash}${title})`;
  });
}

function toPage(srcPath, route) {
  const raw = readFileSync(join(ROOT, srcPath), 'utf8');
  const lines = raw.split('\n');
  const h1 = lines.findIndex((l) => /^# /.test(l));
  const title = h1 >= 0 ? lines[h1].replace(/^# /, '').replace(/^ADR-(\d+): /, 'ADR-$1: ').trim() : route;
  if (h1 >= 0) lines.splice(h1, 1);
  // `## Heading {#id}` is GitHub's explicit heading id; Astro renders it as text. Strip it, and
  // point `#id` links at the slug Astro generates from the heading (the github-slugger rule).
  const slug = (t) => t.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/ /g, '-');
  const ids = new Map();
  let text = lines.join('\n').replace(/^(#{1,6} )(.*?)\s*\{#([\w-]+)\}\s*$/gm, (_, hashes, heading, id) => {
    ids.set(id, slug(heading));
    return hashes + heading;
  });
  text = text.replace(/\]\(#([\w-]+)\)/g, (m, id) => (ids.has(id) ? `](#${ids.get(id)})` : m));
  const body = rewriteLinks(text.replace(/<!--[\s\S]*?-->/g, ''), srcPath);
  const source = `${GITHUB}${srcPath}`;
  const fm = `---\ntitle: ${JSON.stringify(title)}\neditUrl: ${JSON.stringify(source.replace('/blob/', '/edit/'))}\n---\n\n`;
  const note = `:::note[Generated from the repo]\nThis page is [\`${srcPath}\`](${source}), copied in at build time.\n:::\n\n`;
  const out = join(DOCS, route === 'spec' || route === 'adr' ? `${route}/index.md` : `${route}.md`);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, fm + note + body.trimStart());
}

rmSync(join(DOCS, 'spec'), { recursive: true, force: true });
rmSync(join(DOCS, 'adr'), { recursive: true, force: true });
for (const [src, route] of pages) toPage(src, route);

writeFileSync(join(DOCS, 'options.md'), execFileSync('bash', [join(SITE, 'scripts/options-page.sh')], { encoding: 'utf8' }));

mkdirSync(join(SITE, 'public'), { recursive: true });
copyFileSync(join(ROOT, 'install.sh'), join(SITE, 'public/install.sh'));

console.log(`sync-content: ${pages.size} page(s) from the repo, the options page, and /install.sh`);
