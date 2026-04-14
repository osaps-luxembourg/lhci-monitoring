/**
 * RAWeb 12.5 — La page offre un moyen de contact accessible.
 * Détection : lien dont le href ou le texte indique un moyen de contact
 * (mailto:, tel:, /contact, texte "contact", "nous écrire", etc.).
 */

const CONTACT_TEXT_PATTERNS = [
  /\bcontact\b/i,
  /nous\s+(écrire|joindre|contacter)/i,
  /écrivez[\s-]nous/i,
  /write\s+to\s+us/i,
  /get\s+in\s+touch/i,
];

export default class RawebContactLink {
  static get meta() {
    return {
      id: 'raweb-contact-link',
      title: 'Moyen de contact accessible (RAWeb 12.5)',
      failureTitle: 'Aucun moyen de contact trouvé (RAWeb 12.5)',
      description:
        'La page doit permettre à l\'utilisateur d\'accéder à un moyen de contact ' +
        '(formulaire, adresse e-mail, numéro de téléphone, etc.). ' +
        'Critère RAWeb 12.5. ' +
        '[En savoir plus](https://accessibilite.public.lu/fr/raweb1/criteres.html#crit-12-5).',
      requiredArtifacts: ['AnchorElements'],
    };
  }

  static audit(artifacts) {
    const anchors = artifacts.AnchorElements;

    const found = anchors.some(a => {
      const href = (a.href || a.rawHref || '').toLowerCase();
      const text = (a.text || '').trim();

      return (
        href.startsWith('mailto:') ||
        href.startsWith('tel:') ||
        href.includes('/contact') ||
        CONTACT_TEXT_PATTERNS.some(p => p.test(text))
      );
    });

    if (found) {
      return { score: 1 };
    }

    return {
      score: 0,
      details: { type: 'list', items: [] },
    };
  }
}
