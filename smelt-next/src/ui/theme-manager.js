/**
 * Smelt Next — Theme Manager
 */

export class ThemeManager {
  constructor(eventBus, toggleButton, statusLabel) {
    this.bus = eventBus;
    this.toggleButton = toggleButton;
    this.statusLabel = statusLabel;
    this.currentMode = localStorage.getItem('smelt_theme') || 'system'; // 'system' | 'dark' | 'light'

    this.init();
  }

  init() {
    this.applyTheme(this.currentMode);

    if (window.matchMedia) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: light)');
      mediaQuery.addEventListener('change', () => {
        if (this.currentMode === 'system') {
          this.applyTheme('system');
        }
      });
    }

    if (this.toggleButton) {
      this.toggleButton.addEventListener('click', () => this.cycleTheme());
    }
  }

  applyTheme(mode) {
    this.currentMode = mode;
    localStorage.setItem('smelt_theme', mode);

    let isSystemLight = false;
    try {
      if (window.matchMedia) {
        isSystemLight = window.matchMedia('(prefers-color-scheme: light)').matches;
      }
    } catch (e) {
      isSystemLight = false;
    }

    if (mode === 'system') {
      // Default to Dark unless System explicitly prefers Light
      const effectiveTheme = isSystemLight ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', effectiveTheme);
      if (this.statusLabel) {
        this.statusLabel.textContent = `Auto (${effectiveTheme === 'dark' ? 'Dark' : 'Light'})`;
      }
    } else {
      document.documentElement.setAttribute('data-theme', mode);
      if (this.statusLabel) {
        this.statusLabel.textContent = mode === 'dark' ? 'Dark' : 'Light';
      }
    }

    this.bus.emit('theme:changed', { mode, active: document.documentElement.getAttribute('data-theme') });
  }

  cycleTheme() {
    if (this.currentMode === 'system') {
      this.applyTheme('dark');
    } else if (this.currentMode === 'dark') {
      this.applyTheme('light');
    } else {
      this.applyTheme('system');
    }
  }
}
