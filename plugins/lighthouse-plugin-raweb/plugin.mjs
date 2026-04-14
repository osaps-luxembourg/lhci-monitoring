/**
 * lighthouse-plugin-raweb
 * Critères du Référentiel d'Accessibilité Web (RAWeb) du Luxembourg
 * non couverts par axe-core / Lighthouse natif.
 *
 * Critères implémentés :
 *   12.1 — Au moins deux moyens de navigation (informatif)
 *   12.5 — Moyen de contact accessible
 *   12.6 — Lien d'évitement présent
 *   13.3 — Pas de rafraîchissement automatique
 *   14.1 — Déclaration d'accessibilité présente
 */
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

export default {
  audits: [
    { path: join(__dirname, 'audits/raweb-accessibility-statement.mjs') },
    { path: join(__dirname, 'audits/raweb-skip-links.mjs') },
    { path: join(__dirname, 'audits/raweb-no-meta-refresh.mjs') },
    { path: join(__dirname, 'audits/raweb-contact-link.mjs') },
    { path: join(__dirname, 'audits/raweb-multiple-navigation.mjs') },
  ],
  category: {
    title: 'RAWeb Luxembourg',
    description:
      'Critères du Référentiel d\'Accessibilité Web (RAWeb) du Luxembourg ' +
      'non couverts par axe-core. Certains critères nécessitent une vérification manuelle complémentaire.',
    auditRefs: [
      { id: 'raweb-accessibility-statement', weight: 1 },
      { id: 'raweb-skip-links',              weight: 1 },
      { id: 'raweb-no-meta-refresh',         weight: 1 },
      { id: 'raweb-contact-link',            weight: 1 },
      { id: 'raweb-multiple-navigation',     weight: 0 },  // informatif uniquement
    ],
  },
};
