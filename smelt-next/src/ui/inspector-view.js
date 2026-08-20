/**
 * Smelt Next — ROM Inspector Modal View
 */
export class InspectorView {
  constructor(eventBus, modalElement) {
    this.bus = eventBus;
    this.modal = modalElement;
    this.content = modalElement ? modalElement.querySelector('.inspector-content') : null;
    this.closeBtn = modalElement ? modalElement.querySelector('.modal-close') : null;

    this.bindEvents();
    this.subscribeEvents();
  }

  bindEvents() {
    if (this.closeBtn) {
      this.closeBtn.addEventListener('click', () => this.hide());
    }
    if (this.modal) {
      this.modal.addEventListener('click', (e) => {
        if (e.target === this.modal) this.hide();
      });
    }
  }

  subscribeEvents() {
    this.bus.on('ui:inspect-rom', (item) => this.show(item));
  }

  show(item) {
    if (!this.modal || !this.content) return;

    const { file, name, size, analysis } = item;
    const sizeMB = (size / (1024 * 1024)).toFixed(2);
    const sizeGB = (size / (1024 * 1024 * 1024)).toFixed(2);
    const displaySize = size > 1024 * 1024 * 1024 ? `${sizeGB} GB` : `${sizeMB} MB`;

    let statusBadge = '';
    if (analysis?.analysisState === 'clean') {
      statusBadge = '<span class="status-pill status-clean">Clean · NoCrypto Active</span>';
    } else if (analysis?.analysisState === 'patch') {
      statusBadge = '<span class="status-pill status-patch">Patch Required · Missing NoCrypto Flag</span>';
    } else if (analysis?.analysisState === 'cia') {
      statusBadge = '<span class="status-pill status-cia">CIA Archive Container</span>';
    } else {
      statusBadge = '<span class="status-pill status-decrypt">Encrypted NCCH · Requires Keys</span>';
    }

    const noCryptoStatus = analysis?.noCrypto
      ? '<span style="color:#34d399;font-weight:700;">Active (Decrypted)</span>'
      : '<span style="color:#f87171;font-weight:700;">Disabled (Encrypted / Missing)</span>';

    const partitionsList = analysis?.partitions?.map(p => `
      <div class="partition-card">
        <div class="part-header">
          <span class="part-index">Partition ${p.index}</span>
          <span class="part-size">${(p.byteLength / (1024 * 1024)).toFixed(2)} MB</span>
        </div>
        <div class="part-meta">
          <span>Offset: 0x${p.byteOffset.toString(16).toUpperCase()}</span>
          <span>Sectors: ${p.lengthSectors}</span>
        </div>
      </div>
    `).join('') || '<div class="empty-hint">Standard primary partition</div>';

    this.content.innerHTML = `
      <div class="inspector-header">
        <div class="insp-type-badge">${analysis?.isCIA ? 'CIA' : (analysis?.isNCSD ? 'NCSD' : 'NCCH')}</div>
        <div class="header-details">
          <h2 class="rom-name">${name}</h2>
          <div class="rom-status-row">
            ${statusBadge}
            <span class="size-tag">${displaySize}</span>
          </div>
        </div>
      </div>

      <div class="inspector-grid">
        <div class="inspector-card">
          <h3>ID · Metadata</h3>
          <div class="prop-table">
            <div class="prop-row">
              <span class="prop-label">Title ID</span>
              <span class="prop-value mono">${analysis?.titleId || 'Unknown'}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Product Code</span>
              <span class="prop-value mono">${analysis?.productCode || 'CTR-N-3DS'}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Maker Code</span>
              <span class="prop-value mono">${analysis?.makerCode || '00'}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Container</span>
              <span class="prop-value">${analysis?.isNCSD ? 'NCSD Card Image (.3ds/.cci)' : (analysis?.isCIA ? 'CIA Archive' : 'Direct NCCH')}</span>
            </div>
          </div>
        </div>

        <div class="inspector-card">
          <h3>Crypto · Health</h3>
          <div class="prop-table">
            <div class="prop-row">
              <span class="prop-label">NoCrypto Flag (0x18F)</span>
              <span class="prop-value">${noCryptoStatus}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Fixed Crypto Key</span>
              <span class="prop-value">${analysis?.fixedCrypto ? 'Yes' : 'No'}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Media Unit</span>
              <span class="prop-value">${analysis?.mediaUnit ? `${analysis.mediaUnit} bytes` : '512 bytes'}</span>
            </div>
            <div class="prop-row">
              <span class="prop-label">Assessment</span>
              <span class="prop-value explanation">${analysis?.stateExplanation || 'Ready for processing'}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="inspector-section">
        <h3>Partition Map</h3>
        <div class="partition-grid">
          ${partitionsList}
        </div>
      </div>
    `;

    this.modal.classList.remove('hidden');
  }

  hide() {
    if (this.modal) this.modal.classList.add('hidden');
  }
}
