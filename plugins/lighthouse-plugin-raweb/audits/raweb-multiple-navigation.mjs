/**
 * RAWeb 12.1 — La page propose au moins deux moyens de navigation.
 * Détection : menu nav, moteur de recherche, plan du site, fil d'Ariane.
 * Audit informatif (poids 0) : une vérification manuelle reste recommandée.
 */
export default class RawebMultipleNavigation {
  static get meta() {
    return {
      id: 'raweb-multiple-navigation',
      title: 'Au moins deux moyens de navigation (RAWeb 12.1)',
      failureTitle: 'Moins de deux moyens de navigation détectés (RAWeb 12.1)',
      description:
        'La page doit proposer au moins deux moyens de navigation parmi : ' +
        'menu principal, moteur de recherche, plan du site, fil d\'Ariane. ' +
        'Critère RAWeb 12.1. Une vérification manuelle est recommandée. ' +
        '[En savoir plus](https://accessibilite.public.lu/fr/raweb1/criteres.html#crit-12-1).',
      scoreDisplayMode: 'informative',
      requiredArtifacts: ['MainDocumentContent', 'AnchorElements'],
    };
  }

  static audit(artifacts) {
    const html = artifacts.MainDocumentContent || '';
    const anchors = artifacts.AnchorElements;
    const detected = [];

    // 1. Menu de navigation : balise <nav> ou role="navigation"
    const hasNav =
      /<nav[\s>]/i.test(html) ||
      /role\s*=\s*["']?navigation/i.test(html);
    if (hasNav) detected.push('Menu de navigation (<nav> ou role="navigation")');

    // 2. Moteur de recherche : input type="search" ou role="search"
    const hasSearch =
      /<input[^>]+type\s*=\s*["']?search/i.test(html) ||
      /role\s*=\s*["']?search/i.test(html);
    if (hasSearch) detected.push('Moteur de recherche');

    // 3. Plan du site : lien dont href ou texte contient "sitemap" / "plan du site"
    const hasSitemap = anchors.some(a => {
      const href = (a.href || a.rawHref || '').toLowerCase();
      const text = (a.text || '').toLowerCase();
      return (
        href.includes('sitemap') ||
        href.includes('plan-du-site') ||
        href.includes('plan_du_site') ||
        text.includes('plan du site') ||
        text.includes('sitemap')
      );
    });
    if (hasSitemap) detected.push('Plan du site');

    // 4. Fil d'Ariane : aria-label breadcrumb ou classe CSS breadcrumb
    const hasBreadcrumb =
      /aria-label\s*=\s*["'][^"']*(?:breadcrumb|fil.{0,10}ari)/i.test(html) ||
      /class\s*=\s*["'][^"']*breadcrumb/i.test(html) ||
      /typeof\s*=\s*["']?BreadcrumbList/i.test(html);
    if (hasBreadcrumb) detected.push('Fil d\'Ariane');

    const score = detected.length >= 2 ? 1 : 0;

    return {
      score,
      displayValue: `${detected.length} moyen(s) détecté(s) sur 2 requis`,
      details: {
        type: 'list',
        items: detected.map(text => ({ type: 'text', text })),
      },
    };
  }
}
