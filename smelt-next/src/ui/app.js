/**
 * Smelt Next — Main Application Bootstrap & Orchestrator
 */
import { globalEventBus } from '../core/event-bus.js';
import { QueueStore } from '../core/queue-store.js';
import { ForgeService } from '../services/forge-service.js';
import { DownloadService } from '../services/download-service.js';
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
      autoDownloadCheck: document.getElementById('check-auto-download'),
      addFileInput: document.getElementById('queue-file-input'),
      panel: document.getElementById('view-queue')
    });

    // Console & Telemetry View
    this.consoleView = new ConsoleView(this.bus, {
      container: document.getElementById('console-output'),
      speed: document.getElementById('hud-speed'),
      eta: document.getElementById('hud-eta'),
      task: null,
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
    const hasCrypto = typeof window !== 'undefined' && window.crypto && window.crypto.subtle;
    const threads = navigator.hardwareConcurrency || 4;
    const level = hasCrypto ? LOG_LEVEL.SUCCESS : LOG_LEVEL.WARN;
    const msg = hasCrypto
      ? `WebCrypto AES online · ${threads} cores · seeddb bundled`
      : `WebCrypto unavailable — decryption disabled in this browser`;
    this.bus.emit('log', { level, text: msg });
  }

  wireEvents() {
    // 1. Files Ingested from Dropzone, File Picker, or Queue Panel
    this.bus.on('files:ingested', (files) => {
      if (!files || files.length === 0) return;

      const viewDropzone = document.getElementById('view-dropzone');
      const viewQueue = document.getElementById('view-queue');
      const cartIcon = document.querySelector('.cartridge-mockup-icon');
      const isAlreadyInQueue = viewQueue?.classList.contains('active');

      const processIngestedFiles = () => {
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
      };

      if (isAlreadyInQueue) {
        // In Queue mode: add files instantly
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: `Queued ${files.length} ROM file(s).` });
        processIngestedFiles();
      } else if (viewDropzone && viewQueue) {
        // In Dropzone mode: trigger snappy 3DS cartridge "click-in" tactile micro-animation
        if (cartIcon) {
          cartIcon.classList.add('cartridge-inserting');
        }

        // Snappy transition (~350ms) to queue view
        setTimeout(() => {
          if (cartIcon) {
            cartIcon.classList.remove('cartridge-inserting');
          }
          viewDropzone.classList.remove('active');
          viewQueue.classList.add('active');
          processIngestedFiles();
        }, 350);
      } else {
        processIngestedFiles();
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

    // 4b. SeedDB Upload Listener
    const seeddbInput = document.getElementById('seeddb-file-input');
    if (seeddbInput) {
      seeddbInput.addEventListener('change', async (e) => {
        const file = e.target.files?.[0];
        if (file) {
          try {
            const buf = await file.arrayBuffer();
            const count = this.forgeService.loadSeedDB(buf);
            this.bus.emit('log', {
              level: LOG_LEVEL.SUCCESS,
              text: `SeedDB updated! Loaded ${count || 'custom'} title seeds from ${file.name}.`
            });
          } catch (err) {
            this.bus.emit('log', {
              level: LOG_LEVEL.ERROR,
              text: `Failed to load ${file.name}: ${err.message}`
            });
          }
          seeddbInput.value = '';
        }
      });
    }

    // 5. Automatic Download upon smelt completion if enabled
    this.bus.on('forge:item-completed', ({ resultBlob, finalFilename }) => {
      const autoDownloadCheck = document.getElementById('check-auto-download');
      if (autoDownloadCheck && autoDownloadCheck.checked && resultBlob && finalFilename) {
        this.downloadService.downloadBlob(resultBlob, finalFilename);
      }
    });

    // 6. Clock Initialization & Telemetry
    const clockEl = document.getElementById('sys-clock');
    const updateClock = () => {
      if (clockEl) {
        clockEl.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      }
    };
    updateClock();
    setInterval(updateClock, 1000);

    const threadsEl = document.getElementById('hud-threads');
    if (threadsEl) {
      const cores = navigator.hardwareConcurrency || 4;
      threadsEl.textContent = cores;
    }

    // 7. Eject & View Toggle
    const toggleToDropzone = () => {
      const viewDropzone = document.getElementById('view-dropzone');
      const viewQueue = document.getElementById('view-queue');
      if (viewDropzone && viewQueue) {
        viewQueue.classList.remove('active');
        viewDropzone.classList.add('active');
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'Card tray ejected. Switched to Dropzone.' });
      }
    };

    const toggleToQueue = () => {
      const viewDropzone = document.getElementById('view-dropzone');
      const viewQueue = document.getElementById('view-queue');
      if (viewDropzone && viewQueue) {
        viewDropzone.classList.remove('active');
        viewQueue.classList.add('active');
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'Switched to ROM Queue.' });
      }
    };

    document.getElementById('btn-eject-top')?.addEventListener('click', toggleToDropzone);

    // 8. Hardware & Touch Button Bindings
    // A Button / Touch Smelt
    const handleForgeAll = () => {
      document.getElementById('btn-forge-all')?.click();
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'A Button pressed: Triggered Smelt All.' });
    };
    document.getElementById('btn-hw-a')?.addEventListener('click', handleForgeAll);
    document.getElementById('touch-btn-forge')?.addEventListener('click', handleForgeAll);

    // B Button / Touch Clear
    const handleClearQueue = () => {
      document.getElementById('btn-clear-all')?.click();
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'B Button pressed: Cleared Active Queue.' });
    };
    document.getElementById('btn-hw-b')?.addEventListener('click', handleClearQueue);
    document.getElementById('touch-btn-clear')?.addEventListener('click', handleClearQueue);

    // X Button / Touch Format Cycle
    const handleCycleFormat = () => {
      const select = document.getElementById('select-format');
      if (select) {
        select.selectedIndex = (select.selectedIndex + 1) % select.options.length;
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: `X Button pressed: Format set to ${select.options[select.selectedIndex].text}` });
      }
    };
    document.getElementById('btn-hw-x')?.addEventListener('click', handleCycleFormat);
    document.getElementById('touch-btn-format')?.addEventListener('click', handleCycleFormat);

    // Y Button (Toggle Auto-Download)
    document.getElementById('btn-hw-y')?.addEventListener('click', () => {
      const check = document.getElementById('check-auto-download');
      if (check) {
        check.checked = !check.checked;
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: `Y Button pressed: Auto-Save is now ${check.checked ? 'ENABLED' : 'DISABLED'}` });
      }
    });

    // Select Button / Touch Clear Log
    const handleClearLog = () => {
      document.getElementById('btn-clear-console')?.click();
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'Console output cleared.' });
    };
    document.getElementById('btn-hw-select')?.addEventListener('click', handleClearLog);
    document.getElementById('btn-touch-clear-log')?.addEventListener('click', handleClearLog);

    // Start Button / Touch Export Log
    const handleExportLog = () => {
      document.getElementById('btn-export-console')?.click();
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'Console logs exported to disk.' });
    };
    document.getElementById('btn-hw-start')?.addEventListener('click', handleExportLog);
    document.getElementById('btn-touch-export-log')?.addEventListener('click', handleExportLog);

    // HOME Button (Toggle between Dropzone & Queue)
    document.getElementById('btn-hw-home')?.addEventListener('click', () => {
      const viewDropzone = document.getElementById('view-dropzone');
      if (viewDropzone?.classList.contains('active')) {
        toggleToQueue();
      } else {
        toggleToDropzone();
      }
    });

    // D-Pad Scroll Handlers
    const queueList = document.getElementById('queue-list');
    const consoleOutput = document.getElementById('console-output');

    document.getElementById('dpad-up')?.addEventListener('click', () => {
      queueList?.scrollBy({ top: -60, behavior: 'smooth' });
      consoleOutput?.scrollBy({ top: -60, behavior: 'smooth' });
    });
    document.getElementById('dpad-down')?.addEventListener('click', () => {
      queueList?.scrollBy({ top: 60, behavior: 'smooth' });
      consoleOutput?.scrollBy({ top: 60, behavior: 'smooth' });
    });
  }
}

// Bootstrap Application
document.addEventListener('DOMContentLoaded', () => {
  window.smeltApp = new SmeltNextApplication();
});
