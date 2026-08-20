/**
 * Smelt Next — Batch Queue View
 */
import { ROM_STATUS } from '../core/constants.js';

export class QueueView {
  constructor(eventBus, queueStore, elements = {}) {
    this.bus = eventBus;
    this.store = queueStore;
    this.listEl = elements.list;
    this.emptyEl = elements.empty;
    this.forgeAllBtn = elements.forgeAllBtn;
    this.clearAllBtn = elements.clearAllBtn;
    this.formatSelect = elements.formatSelect;
    this.autoDownloadCheck = elements.autoDownloadCheck;
    this.addFileInput = elements.addFileInput;
    this.panelEl = elements.panel;

    this.bindEvents();
    this.subscribeStore();
  }

  bindEvents() {
    if (this.forgeAllBtn) {
      this.forgeAllBtn.addEventListener('click', () => {
        this.bus.emit('batch:request-start', {
          outputFormat: this.formatSelect?.value || 'same'
        });
      });
    }

    if (this.clearAllBtn) {
      this.clearAllBtn.addEventListener('click', () => {
        this.store.clear();
      });
    }

    // Add ROMs file input in queue header
    if (this.addFileInput) {
      this.addFileInput.addEventListener('change', (e) => {
        const files = Array.from(e.target.files || []);
        if (files.length > 0) {
          this.bus.emit('files:ingested', files);
          this.addFileInput.value = '';
        }
      });
    }

    // Drag-and-drop support directly on Queue Panel
    if (this.panelEl) {
      ['dragenter', 'dragover'].forEach(eventName => {
        this.panelEl.addEventListener(eventName, (e) => {
          e.preventDefault();
          e.stopPropagation();
        }, false);
      });

      this.panelEl.addEventListener('drop', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const files = Array.from(e.dataTransfer?.files || []);
        if (files.length > 0) {
          this.bus.emit('files:ingested', files);
        }
      }, false);
    }
  }

  subscribeStore() {
    this.bus.on('queue:updated', (items) => this.render(items));
    this.bus.on('queue:item-updated', (item) => this.renderItem(item));
  }

  render(items) {
    if (!this.listEl || !this.emptyEl) return;

    if (!items || items.length === 0) {
      this.emptyEl.classList.remove('hidden');
      this.listEl.innerHTML = '';
      if (this.forgeAllBtn) this.forgeAllBtn.disabled = true;
      return;
    }

    this.emptyEl.classList.add('hidden');
    if (this.forgeAllBtn) this.forgeAllBtn.disabled = false;

    // Remove old cards that are no longer in store
    const itemIds = new Set(items.map(i => i.id));
    for (const card of Array.from(this.listEl.children)) {
      const cardId = card.id.replace('queue-item-', '');
      if (!itemIds.has(cardId)) {
        card.remove();
      }
    }

    // Render all current items
    for (const item of items) {
      this.renderItem(item);
    }
  }

  renderItem(item) {
    if (!this.listEl) return;

    let el = document.getElementById(`queue-item-${item.id}`);
    if (!el) {
      el = document.createElement('div');
      el.id = `queue-item-${item.id}`;
      el.className = 'queue-card';
      this.listEl.appendChild(el);
    }

    const sizeMB = (item.size / (1024 * 1024)).toFixed(1);
    let stateBadge = '';

    if (item.status === ROM_STATUS.ANALYZING) {
      stateBadge = '<span class="badge badge-analyzing">Analyzing...</span>';
    } else if (item.status === ROM_STATUS.FORGING) {
      stateBadge = `<span class="badge badge-forging">Forging ${item.progress}%</span>`;
    } else if (item.status === ROM_STATUS.COMPLETED) {
      stateBadge = '<span class="badge badge-done">Ready</span>';
    } else if (item.status === ROM_STATUS.ERROR) {
      stateBadge = '<span class="badge badge-error">Failed</span>';
    } else {
      if (item.analysis?.analysisState === 'clean') {
        stateBadge = '<span class="badge badge-clean">Clean</span>';
      } else if (item.analysis?.analysisState === 'patch') {
        stateBadge = '<span class="badge badge-patch">1ms Patch</span>';
      } else if (item.analysis?.analysisState === 'cia') {
        stateBadge = '<span class="badge badge-decrypt">CIA Archive</span>';
      } else {
        stateBadge = '<span class="badge badge-decrypt">Encrypted</span>';
      }
    }

    el.innerHTML = `
      <div class="card-left">
        <div class="rom-icon-badge">3DS</div>
        <div class="rom-info">
          <div class="rom-title-row">
            <span class="rom-filename" title="${item.name}">${item.name}</span>
            ${stateBadge}
          </div>
          <div class="rom-sub-row">
            <span>${sizeMB} MB</span>
            <span>•</span>
            <span class="mono">${item.analysis?.productCode || 'CTR-3DS'}</span>
            <span>•</span>
            <span class="mono">${item.analysis?.titleId || ''}</span>
          </div>
        </div>
      </div>

      <div class="card-progress-zone">
        <div class="mini-progress-bar">
          <div class="mini-progress-fill" style="width: ${item.progress}%"></div>
        </div>
      </div>

      <div class="card-actions">
        <button class="btn-action btn-inspect" title="Inspect ROM details">i</button>
        ${item.status === ROM_STATUS.COMPLETED ? `
          <button class="btn-action btn-download" title="Download decrypted ROM">DL</button>
        ` : `
          <button class="btn-action btn-single-forge" title="Forge this ROM">RUN</button>
        `}
        <button class="btn-action btn-remove" title="Remove">✕</button>
      </div>
    `;

    // Action listeners
    el.querySelector('.btn-inspect')?.addEventListener('click', () => {
      this.bus.emit('ui:inspect-rom', item);
    });

    el.querySelector('.btn-download')?.addEventListener('click', () => {
      if (item.resultBlob && item.finalFilename) {
        this.bus.emit('request:download', { blob: item.resultBlob, filename: item.finalFilename });
      }
    });

    el.querySelector('.btn-single-forge')?.addEventListener('click', () => {
      this.bus.emit('request:forge-single', {
        id: item.id,
        options: { outputFormat: this.formatSelect?.value || 'same' }
      });
    });

    el.querySelector('.btn-remove')?.addEventListener('click', () => {
      this.store.removeItem(item.id);
    });
  }
}
