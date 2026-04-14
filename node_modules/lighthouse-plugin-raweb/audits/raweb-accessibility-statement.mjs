/**
 * RAWeb 14.1 — La page contient un lien vers une déclaration d'accessibilité.
 * Détection : lien dont le href ou le texte contient "accessib".
 */
export default class RawebAccessibilityStatement {
  static get meta() {
    return {
      id: 'raweb-accessibility-statement',
      title: 'Déclaration d\'accessibilité présente (RAWeb 14.1)',
      failureTitle: 'Déclaration d\'accessibilité absente (RAWeb 14.1)',
      description:
        'La page doit contenir un lien vers une déclaration d\'accessibilité. ' +
        'Critère RAWeb 14.1. ' +
        '[En savoir plus](https://accessibilite.public.lu/fr/obligations/declaration-accessibilite.html).',
      requiredArtifacts: ['AnchorElements'],
    };
  }

  static audit(artifacts) {
    const anchors = artifacts.AnchorElements;

    const matches = anchors.filter(a => {
      const href = (a.href || a.rawHref || '').toLowerCase();
      const text = (a.text || '').toLowerCase();
      return href.includes('accessib') || text.includes('accessibilit');
    });

    if (matches.length > 0) {
      return { score: 1 };
    }

    return {
      score: 0,
      details: { type: 'list', items: [] },
    };
  }
}
