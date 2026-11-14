(() => {
  const key = '__jenaLinkPolicy';
  if (!globalThis[key]) {
    const state = { enabled: false };
    globalThis[key] = state;
    const handleLink = event => {
      const explicitNewContext = event.metaKey || event.shiftKey || event.button === 1;
      if ((!state.enabled && !explicitNewContext) || !event.isTrusted || event.defaultPrevented ||
          ![0, 1].includes(event.button) || event.ctrlKey || event.altKey) return;
      const anchor = event.composedPath().find(node => node instanceof HTMLAnchorElement);
      if (!anchor || anchor.hasAttribute('download')) return;
      const target = anchor.getAttribute('target') ?? document.querySelector('base[target]')?.getAttribute('target') ?? '';
      if (target && target.toLowerCase() !== '_self') return;
      let destination;
      try { destination = new URL(anchor.href); } catch { return; }
      if (!['http:', 'https:'].includes(destination.protocol)) return;
      const current = new URL(location.href);
      if (destination.origin === current.origin && destination.pathname === current.pathname &&
          destination.search === current.search) return;
      const oldTarget = anchor.getAttribute('target');
      anchor.setAttribute('target', '_blank');
      setTimeout(() => {
        if (anchor.getAttribute('target') !== '_blank') return;
        if (oldTarget === null) anchor.removeAttribute('target');
        else anchor.setAttribute('target', oldTarget);
      }, 0);
    };
    window.addEventListener('click', handleLink, true);
    window.addEventListener('auxclick', handleLink, true);
  }
  globalThis[key].enabled = JENA_ENABLED;
})();
