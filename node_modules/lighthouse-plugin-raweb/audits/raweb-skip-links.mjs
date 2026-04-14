/**
 * RAWeb 12.6 / 12.7 — La page contient un lien d'évitement vers le contenu principal.
 * Détection : ancre interne (#...) dont le texte ou la cible correspond à un lien d'évitement.
 */

const SKIP_TEXT_PATTERNS = [
  /aller.+au\s+contenu/i,
  /aller.+au\s+menu/i,
  /passer.+au\s+contenu/i,
  /passer.+la\s+navigation/i,
  /lien.+d.?évitement/i,
  /contenu\s+principal/i,
  /skip\s+to\s+(main|content|navigation)/i,
  /go\s+to\s+(main|content)/i,
];

const COMMON_SKIP_TARGETS = [
  '#main', '#content', '#contenu', '#main-content',
  '#maincontent', '#page-content', '#primary',
];

export default class RawebSkipLinks {
  static get meta() {
    return {
      id: 'raweb-skip-links',
      title: 'Lien d\'évitement présent (RAWeb 12.6)',
      failureTitle: 'Lien d\'évitement absent (RAWeb 12.6)',
      description:
        'La page doit contenir au moins un lien permettant d\'accéder directement au ' +
        'contenu principal (lien d\'évitement). ' +
        'Critère RAWeb 12.6. ' +
        '[En savoir plus](https://accessibilite.public.lu/fr/raweb1/criteres.html#crit-12-6).',
      requiredArtifacts: ['AnchorElements'],
    };
  }

  static audit(artifacts) {
    const anchors = artifacts.AnchorElements;

    // Liens internes uniquement (#...)
    const internalAnchors = anchors.filter(
      a => a.rawHref && a.rawHref.startsWith('#')
    );

    // Correspondance par le texte
    const byText = internalAnchors.find(a =>
      SKIP_TEXT_PATTERNS.some(p => p.test((a.text || '').trim()))
    );
    if (byText) return { score: 1 };

    // Correspondance par la cible connue
    const byTarget = internalAnchors.find(a =>
      COMMON_SKIP_TARGETS.includes((a.rawHref || '').toLowerCase())
    );
    if (byTarget) return { score: 1 };

    return {
      score: 0,
      details: { type: 'list', items: [] },
    };
  }
}
