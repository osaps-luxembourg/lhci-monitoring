/**
 * RAWeb 13.3 — La page ne se rafraîchit pas automatiquement.
 * Détection : présence de <meta http-equiv="refresh">.
 */
export default class RawebNoMetaRefresh {
  static get meta() {
    return {
      id: 'raweb-no-meta-refresh',
      title: 'Pas de rafraîchissement automatique (RAWeb 13.3)',
      failureTitle: 'Rafraîchissement automatique détecté (RAWeb 13.3)',
      description:
        'La page ne doit pas utiliser de balise <meta http-equiv="refresh"> ' +
        'pour se rafraîchir ou rediriger automatiquement. ' +
        'Critère RAWeb 13.3. ' +
        '[En savoir plus](https://accessibilite.public.lu/fr/raweb1/criteres.html#crit-13-3).',
      requiredArtifacts: ['MetaElements'],
    };
  }

  static audit(artifacts) {
    const metas = artifacts.MetaElements;
    const refresh = metas.find(m => m.httpEquiv === 'refresh');

    if (!refresh) {
      return { score: 1 };
    }

    return {
      score: 0,
      details: {
        type: 'table',
        headings: [{ key: 'content', itemType: 'text', text: 'Valeur de la balise refresh' }],
        items: [{ content: refresh.content || '' }],
      },
    };
  }
}
