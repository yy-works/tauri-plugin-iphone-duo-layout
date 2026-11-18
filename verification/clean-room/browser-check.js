async page => {
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  const result = [];
  for (const [width, height, mode, navigation] of [[1000, 800, 'wide', 240], [466, 678, 'compact', 0]]) {
    await page.setViewportSize({width, height});
    await page.waitForFunction(({mode, width, height}) => {
      const root = document.querySelector('#shell');
      return root?.dataset.layoutReady === 'true' && root.dataset.layout === mode && JSON.parse(document.querySelector('#metrics').textContent).viewport.width === width && JSON.parse(document.querySelector('#metrics').textContent).viewport.height === height;
    }, {mode, width, height});
    const current = await page.evaluate(() => ({
      metrics: JSON.parse(document.querySelector('#metrics').textContent),
      visible: getComputedStyle(document.querySelector('#shell')).visibility,
      navHidden: document.querySelector('#nav').hidden,
      content: document.querySelector('#content').getBoundingClientRect().toJSON()
    }));
    if (current.metrics.navigationWidth !== navigation || current.visible !== 'visible' || current.navHidden !== (mode === 'compact')) throw new Error(JSON.stringify(current));
    if (Math.abs(current.content.width - current.metrics.contentRect.width) > 1) throw new Error('Content rect mismatch');
    result.push({width, height, mode: current.metrics.mode, navigation: current.metrics.navigationWidth, contentWidth: current.content.width, visible: current.visible});
  }
  if (errors.length) throw new Error(JSON.stringify(errors));
  return {result, errors};
}
