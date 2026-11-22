(() => {
  'use strict';

  const MAX_MAG_SCALE = 1.55;
  const MAG_RADIUS_PX = 116;

  const htmlEl = document.documentElement;
  const themeToggleBtn = document.getElementById('theme-toggle');
  const macDesktop = document.getElementById('mac-desktop');
  const desktopThemeToggleBtn = document.getElementById('desktop-theme-toggle');
  const desktopThemeLabel = document.getElementById('desktop-theme-label');

  const transparencySlider = document.getElementById('transparency-slider');
  const transparencyValue = document.getElementById('transparency-value');
  const swatches = Array.from(document.querySelectorAll('.swatch[data-tint]'));
  const magToggleBtn = document.getElementById('mag-toggle');

  const tooltip = document.getElementById('dock-tooltip');
  const docks = Array.from(document.querySelectorAll('.sim-dock'));

  let magEnabled = true;
  let activeTintRgb = null; // e.g., "10,132,255" or null for neutral clear

  /* ------------------------------------------------------------------------
     Theme Management (Page & Simulated Desktop)
     ------------------------------------------------------------------------ */
  function setDesktopTheme(theme) {
    if (!macDesktop) return;
    macDesktop.setAttribute('data-desktop-theme', theme);
    if (desktopThemeLabel) {
      desktopThemeLabel.textContent = theme === 'light' ? 'Light' : 'Dark';
    }
    if (desktopThemeToggleBtn) {
      desktopThemeToggleBtn.setAttribute('aria-pressed', theme === 'light' ? 'true' : 'false');
      desktopThemeToggleBtn.classList.toggle('is-on', theme === 'light');
    }
    updateGlassAppearance();
  }

  function setPageTheme(theme) {
    htmlEl.setAttribute('data-theme', theme);
    if (themeToggleBtn) {
      themeToggleBtn.setAttribute(
        'aria-label',
        theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'
      );
    }
    const metaTheme = document.querySelector('meta[name="theme-color"]');
    if (metaTheme) {
      metaTheme.setAttribute('content', theme === 'dark' ? '#070A12' : '#F3F6FC');
    }
    setDesktopTheme(theme);
    try {
      localStorage.setItem('dockplus-theme', theme);
    } catch (_) {
      // Ignore storage failures in restricted contexts
    }
  }

  // Initialize theme from saved preference or OS preference
  (() => {
    let initial = 'dark';
    try {
      const saved = localStorage.getItem('dockplus-theme');
      if (saved === 'light' || saved === 'dark') {
        initial = saved;
      } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        initial = 'light';
      }
    } catch (_) {
      initial = 'dark';
    }
    setPageTheme(initial);
  })();

  if (themeToggleBtn) {
    themeToggleBtn.addEventListener('click', () => {
      const current = htmlEl.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
      setPageTheme(current === 'dark' ? 'light' : 'dark');
    });
  }

  if (desktopThemeToggleBtn) {
    desktopThemeToggleBtn.addEventListener('click', () => {
      const current = macDesktop?.getAttribute('data-desktop-theme') === 'light' ? 'light' : 'dark';
      setDesktopTheme(current === 'dark' ? 'light' : 'dark');
    });
  }

  /* ------------------------------------------------------------------------
     Liquid Glass Transparency & Tint Controls
     ------------------------------------------------------------------------ */
  function updateGlassAppearance() {
    if (!macDesktop || !transparencySlider) return;

    const pct = Number(transparencySlider.value);
    const t = Math.min(Math.max(pct / 100, 0), 1); // 0 = Opaque, 1 = Clear
    const isLightDesktop = macDesktop.getAttribute('data-desktop-theme') === 'light';

    if (transparencyValue) {
      transparencyValue.textContent = `${pct}%`;
    }

    // Higher opacity & blur near Opaque (0%), crystal-clear near Clear (100%)
    const baseOpaque = isLightDesktop ? 0.78 : 0.66;
    const baseClear = isLightDesktop ? 0.14 : 0.08;
    const alpha = baseOpaque - t * (baseOpaque - baseClear);
    const blur = 22 - t * 18.5;

    const defaultRgb = isLightDesktop ? '255, 255, 255' : '255, 255, 255';
    const tintRgb = activeTintRgb || defaultRgb;
    const tintAlpha = activeTintRgb ? 0.28 - t * 0.14 : 0.10 - t * 0.07;

    macDesktop.style.setProperty('--dock-alpha', alpha.toFixed(3));
    macDesktop.style.setProperty('--dock-blur', `${blur.toFixed(1)}px`);
    macDesktop.style.setProperty('--dock-tint-rgb', tintRgb);
    macDesktop.style.setProperty('--dock-tint-alpha', tintAlpha.toFixed(3));
  }

  if (transparencySlider) {
    transparencySlider.addEventListener('input', updateGlassAppearance);
  }

  swatches.forEach((swatch) => {
    swatch.addEventListener('click', () => {
      swatches.forEach((s) => s.classList.remove('is-active'));
      swatch.classList.add('is-active');
      const tint = swatch.getAttribute('data-tint');
      activeTintRgb = tint && tint !== 'none' ? tint : null;
      updateGlassAppearance();
    });
  });

  if (magToggleBtn) {
    magToggleBtn.addEventListener('click', () => {
      magEnabled = !magEnabled;
      magToggleBtn.classList.toggle('is-on', magEnabled);
      magToggleBtn.setAttribute('aria-pressed', magEnabled ? 'true' : 'false');
      if (!magEnabled) {
        docks.forEach((dock) => resetDockMagnification(dock));
      }
    });
  }

  updateGlassAppearance();

  /* ------------------------------------------------------------------------
     Cosine-Wave Dock Magnification & Hover Tooltip
     ------------------------------------------------------------------------ */
  function hideTooltip() {
    if (!tooltip) return;
    tooltip.classList.remove('is-visible', 'is-left');
    tooltip.setAttribute('aria-hidden', 'true');
  }

  function showTooltipForItem(item, orientation) {
    if (!tooltip || !macDesktop) return;
    const label = item.getAttribute('data-label');
    if (!label) return;

    const desktopRect = macDesktop.getBoundingClientRect();
    const itemRect = item.getBoundingClientRect();

    tooltip.textContent = label;
    tooltip.setAttribute('aria-hidden', 'false');

    if (orientation === 'vertical') {
      tooltip.classList.add('is-left');
      const x = itemRect.left - desktopRect.left - 12;
      const y = itemRect.top - desktopRect.top + itemRect.height / 2;
      tooltip.style.left = `${x}px`;
      tooltip.style.top = `${y}px`;
    } else {
      tooltip.classList.remove('is-left');
      const x = itemRect.left - desktopRect.left + itemRect.width / 2;
      const y = itemRect.top - desktopRect.top - 36;
      tooltip.style.left = `${x}px`;
      tooltip.style.top = `${Math.max(34, y)}px`;
    }

    tooltip.classList.add('is-visible');
  }

  function resetDockMagnification(dock) {
    dock.classList.add('is-resting');
    const items = dock.querySelectorAll('.dock-item');
    items.forEach((item) => {
      item.style.setProperty('--mag', '1');
    });
  }

  docks.forEach((dock) => {
    const orientation = dock.getAttribute('data-orientation') === 'vertical' ? 'vertical' : 'horizontal';
    const items = Array.from(dock.querySelectorAll('.dock-item'));
    const anchor = dock.closest('.sim-dock-anchor');

    dock.addEventListener('pointerenter', () => {
      dock.classList.remove('is-resting');
      if (anchor) anchor.classList.add('is-hovered');
    });

    dock.addEventListener('pointermove', (event) => {
      if (event.pointerType === 'touch') return;

      const pointerCoord = orientation === 'vertical' ? event.clientY : event.clientX;

      if (magEnabled) {
        items.forEach((item) => {
          const rect = item.getBoundingClientRect();
          const itemCenter = orientation === 'vertical'
            ? rect.top + rect.height / 2
            : rect.left + rect.width / 2;
          const dist = Math.abs(pointerCoord - itemCenter);

          let scale = 1;
          if (dist < MAG_RADIUS_PX) {
            const cosineFactor = 0.5 * (1 + Math.cos((Math.PI * dist) / MAG_RADIUS_PX));
            scale = 1 + (MAX_MAG_SCALE - 1) * cosineFactor;
          }
          item.style.setProperty('--mag', scale.toFixed(3));
        });
      }

      const hoveredItem = event.target instanceof Element ? event.target.closest('.dock-item') : null;
      if (hoveredItem && dock.contains(hoveredItem)) {
        showTooltipForItem(hoveredItem, orientation);
      } else {
        hideTooltip();
      }
    });

    dock.addEventListener('pointerleave', () => {
      if (anchor) anchor.classList.remove('is-hovered');
      resetDockMagnification(dock);
      hideTooltip();
    });

    // Click to launch bounce + toggle running indicator dot
    items.forEach((item) => {
      item.addEventListener('click', () => {
        item.classList.remove('is-bouncing');
        void item.offsetWidth; // Restart bounce animation cleanly
        item.classList.add('is-bouncing');

        const isRunning = item.getAttribute('data-running') === 'true';
        item.setAttribute('data-running', isRunning ? 'false' : 'true');
      });

      item.addEventListener('animationend', () => {
        item.classList.remove('is-bouncing');
      });
    });
  });

  /* ------------------------------------------------------------------------
     Copy-to-Clipboard Buttons
     ------------------------------------------------------------------------ */
  function fallbackCopy(text) {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
    } finally {
      document.body.removeChild(textarea);
    }
  }

  document.querySelectorAll('.copy-btn[data-copy]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const text = btn.getAttribute('data-copy') || '';
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          fallbackCopy(text);
        }
      } catch (_) {
        fallbackCopy(text);
      }

      const original = btn.textContent;
      btn.textContent = 'Copied!';
      btn.classList.add('is-copied');
      window.setTimeout(() => {
        btn.textContent = original || 'Copy';
        btn.classList.remove('is-copied');
      }, 1500);
    });
  });

  /* ------------------------------------------------------------------------
     Build from Source Tabs
     ------------------------------------------------------------------------ */
  const tabButtons = Array.from(document.querySelectorAll('.tab-btn[data-tab]'));
  const tabPanels = Array.from(document.querySelectorAll('.tab-panel[data-panel]'));

  tabButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const target = btn.getAttribute('data-tab');
      tabButtons.forEach((b) => {
        const active = b === btn;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-selected', active ? 'true' : 'false');
      });
      tabPanels.forEach((panel) => {
        panel.classList.toggle('is-active', panel.getAttribute('data-panel') === target);
      });
    });
  });
})();
