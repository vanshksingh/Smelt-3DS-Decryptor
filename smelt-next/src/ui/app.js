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
      // Trigger Cartridge Animation & View Transition
      const anim = document.getElementById('cartridge-anim');
      const viewDropzone = document.getElementById('view-dropzone');
      const viewQueue = document.getElementById('view-queue');
      
      if (anim && viewDropzone && viewQueue && files.length > 0) {
        // Start animation
        anim.classList.add('animate');
        
        // After "click" (1.5s), swap views
        setTimeout(() => {
          viewDropzone.classList.remove('active');
          viewQueue.classList.add('active');
          anim.classList.remove('animate');
          
          // Process files after animation finishes
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
        }, 1500);
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
      threadsEl.textContent = `Active (${cores}-Core)`;
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
        this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'Switched to Active Queue.' });
      }
    };

    document.getElementById('btn-eject-top')?.addEventListener('click', toggleToDropzone);

    // 8. Hardware & Touch Button Bindings
    // A Button / Touch Forge
    const handleForgeAll = () => {
      document.getElementById('btn-forge-all')?.click();
      this.bus.emit('log', { level: LOG_LEVEL.INFO, text: 'A Button pressed: Triggered Forge All.' });
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
