import BaseGatherer from 'lighthouse/core/gather/base-gatherer.js';

export default class FooterAnchors extends BaseGatherer {
  meta = { supportedModes: ['snapshot', 'navigation'] };

  async snapshot({ driver }) {
    return driver.executionContext.evaluate(
      () => Array.from(document.querySelectorAll('footer a')).map(a => ({
        href: a.href || '',
        rawHref: a.getAttribute('href') || '',
        text: (a.textContent || '').trim(),
      })),
      { args: [] }
    );
  }
}
