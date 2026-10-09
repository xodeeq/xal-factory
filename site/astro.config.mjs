// The factory's documentation site. Most pages are the repo's own markdown (spec/, adr/,
// PRINCIPLES.md, docs/adopting.md), copied in by scripts/sync-content.mjs before every build,
// so the docs are the spec and cannot drift from it. Hand-written pages live in
// src/content/docs/ beside the generated ones (which are gitignored).
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

export default defineConfig({
  site: 'https://factory.getxal.com',
  integrations: [
    starlight({
      title: 'Xal Software Factory',
      description: 'From a one-line idea to a monitored service, with a gate at every step.',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/xodeeq/xal-factory' }],
      editLink: { baseUrl: 'https://github.com/xodeeq/xal-factory/edit/main/site/' },
      customCss: ['./src/styles/theme.css'],
      plugins: [starlightLinksValidator({ errorOnRelativeLinks: false })],
      sidebar: [
        { label: 'Start', items: ['install', 'onboarding', 'credentials', 'options', 'faq'] },
        { label: 'How it works', items: ['spec/lifecycle', 'spec/session-types', 'autonomy', 'principles'] },
        { label: 'The spec', items: [{ autogenerate: { directory: 'spec' } }] },
        { label: 'Decisions', items: [{ autogenerate: { directory: 'adr' } }] },
        { label: 'Adopting', items: ['adopting'] },
      ],
    }),
  ],
});
