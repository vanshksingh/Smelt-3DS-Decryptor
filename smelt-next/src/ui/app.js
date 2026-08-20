/**
 * Smelt Next — Main Application Bootstrap & Orchestrator (Loosely Coupled)
 */
import { globalEventBus } from '../core/event-bus.js';
import { QueueStore } from '../core/queue-store.js';
import { ForgeService } from '../services/forge-service.js';
import { DownloadService } from '../services/download-service.js';
import { ThemeManager } from './theme-manager.js';
import { DropzoneView } from './dropzone-view.js';
import { QueueView } from './queue-view.js';
import { ConsoleView } from './console-view.js';
import { InspectorView } from './inspector-view.js';
import { LOG_LEVEL } from '../core/constants.js';

class SmeltNextApplication {
  constructor() {
    this.bus = globalEventBus;
    this.queue = new QueueStore(this.bus);
    this.downloadService = new DownloadService(this.bus);
    this.forgeService = new ForgeService(this.bus, this.queue);

    this.initViews();
    this.initHardwareHUD();
    this.wireEvents();
  }

  initViews() {
    // Theme Manager
    this.themeManager = new ThemeManager(
      this.bus,
      document.getElementById('btn-theme-toggle'),
      document.getElementById('theme-status-text')
    );

    // Dropzone View
    this.dropzoneView = new DropzoneView(
      this.bus,
      document.getElementById('dropzone'),
      document.getElementById('file-input')
    );

    // Queue View
    this.queueView = new QueueView(this.bus, this.queue, {
      list: document.getElementById('queue-list'),
      empty: document.getElementById('empty-queue'),
      forgeAllBtn: document.getElementById('btn-forge-all'),
      clearAllBtn: document.getElementById('btn-clear-all'),
      formatSelect: document.getElementById('select-format'),
      autoDownloadCheck: document.getElementById('check-auto-download')
    });

    // Console & Telemetry View
    this.consoleView = new ConsoleView(this.bus, {
      container: document.getElementById('console-output'),
      speed: document.getElementById('hud-speed'),
      eta: document.getElementById('hud-eta'),
      task: document.getElementById('hud-task'),
      clearBtn: document.getElementById('btn-clear-console'),
      exportBtn: document.getElementById('btn-export-console')
    });

    // Inspector View
    this.inspectorView = new InspectorView(
      this.bus,
      document.getElementById('inspector-modal')
    );
  }

  initHardwareHUD() {
    const hwBadge = document.getElementById('hardware-badge');
    const hasCrypto = typeof window !== 'undefined' && window.crypto && window.crypto.subtle;
    const threads = navigator.hardwareConcurrency || 4;

    if (hasCrypto && hwBadge) {
      hwBadge.innerHTML = `
        <span class="hw-indicator active"></span>
        <span class="hw-text">Hardware AES Acceleration: <b>Active</b> (${threads} Threads)</span>
      `;
      this.bus.emit('log', {
        level: LOG_LEVEL.SUCCESS,
        text: `Hardware Crypto Acceleration initialized via Web Crypto API (${threads} Logical Cores).`
      });
    } else if (hwBadge) {
      hwBadge.innerHTML = `
        <span class="hw-indicator warn"></span>
        <span class="hw-text">Software Emulation Mode</span>
      `;
    }
  }

  wireEvents() {
    // 1. Files Ingested from Dropzone or File Picker
    this.bus.on('files:ingested', (files) => {
      for (const file of files) {
        if (file.name.toLowerCase().includes('seeddb')) {
          file.arrayBuffer().then((buf) => {
            this.forgeService.loadSeedDB(buf);
          });
        } else {
          const item = this.queue.addItem(file);
          this.forgeService.analyzeROM(item);
        }
      }
    });

    // 2. Batch Forge Request
    this.bus.on('batch:request-start', ({ outputFormat }) => {
      this.forgeService.startBatchForge({ outputFormat });
    });

    // 3. Single Forge Request
    this.bus.on('request:forge-single', ({ id, options }) => {
      this.forgeService.processSingleItem(id, options);
    });

    // 4. Download Request
    this.bus.on('request:download', ({ blob, filename }) => {
      this.downloadService.downloadBlob(blob, filename);
    });

    // 5. Automatic Download upon forge completion if enabled
    this.bus.on('forge:item-completed', ({ resultBlob, finalFilename }) => {
      const autoDownloadCheck = document.getElementById('check-auto-download');
      if (autoDownloadCheck && autoDownloadCheck.checked && resultBlob && finalFilename) {
        this.downloadService.downloadBlob(resultBlob, finalFilename);
      }
    });

    // 6. Hardware Button Bindings (New 3DS XL)
    document.getElementById('btn-hw-a')?.addEventListener('click', () => {
      // Forge All (or Forge next single if implemented)
      document.getElementById('btn-forge-all')?.click();
    });

    document.getElementById('btn-hw-b')?.addEventListener('click', () => {
      // Clear queue
      document.getElementById('btn-clear-all')?.click();
    });

    document.getElementById('btn-hw-x')?.addEventListener('click', () => {
      // Cycle formats
      const select = document.getElementById('select-format');
      if (select) {
        select.selectedIndex = (select.selectedIndex + 1) % select.options.length;
      }
    });

    document.getElementById('btn-hw-y')?.addEventListener('click', () => {
      // Toggle auto-download
      const check = document.getElementById('check-auto-download');
      if (check) check.checked = !check.checked;
    });

    document.getElementById('btn-hw-select')?.addEventListener('click', () => {
      // Clear console
      document.getElementById('btn-clear-console')?.click();
    });

    document.getElementById('btn-hw-start')?.addEventListener('click', () => {
      // Export console
      document.getElementById('btn-export-console')?.click();
    });

    document.getElementById('btn-hw-home')?.addEventListener('click', () => {
      // If we had a Home menu, we'd open it here. For now, just log.
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'HOME button pressed.' });
    });
  }
}

// Bootstrap Application
document.addEventListener('DOMContentLoaded', () => {
  window.smeltApp = new SmeltNextApplication();
});
