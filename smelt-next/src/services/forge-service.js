/**
 * Smelt Next — Web Worker Orchestration & RPC Service
 */
import { ROM_STATUS, LOG_LEVEL } from '../core/constants.js';

export class ForgeService {
  constructor(eventBus, queueStore) {
    this.bus = eventBus;
    this.queue = queueStore;
    this.worker = null;
    this.isProcessingBatch = false;
    this.initWorker();
  }

  initWorker() {
    try {
      if (this.worker) {
        this.worker.terminate();
      }
      this.worker = new Worker(new URL('../workers/decrypt.worker.js', import.meta.url), { type: 'module' });
      this.worker.onmessage = (e) => this.handleWorkerMessage(e.data);
      this.worker.onerror = (err) => {
        this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Worker thread error: ${err.message}` });
      };
    } catch (err) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Failed to initialize Web Worker: ${err.message}` });
    }
  }

  handleWorkerMessage(data) {
    const { type, fileId, analysis, percent, speedMBs, etaSeconds, text, level, resultBlob, finalFilename, error, count } = data;

    switch (type) {
      case 'SEEDDB_LOADED':
        this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `SeedDB ready! Loaded ${count} title seeds.` });
        break;

      case 'ANALYSIS_COMPLETE':
        this.queue.updateItem(fileId, {
          analysis,
          status: ROM_STATUS.READY
        });
        this.bus.emit('log', {
          level: LOG_LEVEL.INFO,
          text: `Analyzed [${analysis.fileName}]: State = ${analysis.analysisState?.toUpperCase()} (Title ID: ${analysis.titleId || 'Unknown'})`
        });
        break;

      case 'LOG':
        this.bus.emit('log', { level: level || LOG_LEVEL.INFO, text });
        break;

      case 'PROGRESS':
        this.queue.updateItem(fileId, {
          progress: percent,
          speedMBs
        });
        this.bus.emit('telemetry:progress', {
          fileId,
          percent,
          speedMBs,
          etaSeconds
        });
        break;

      case 'PROCESS_COMPLETE':
        this.queue.updateItem(fileId, {
          status: ROM_STATUS.COMPLETED,
          progress: 100,
          resultBlob,
          finalFilename
        });
        this.bus.emit('forge:item-completed', { fileId, resultBlob, finalFilename });
        this.processNextInBatch();
        break;

      case 'PROCESS_ERROR':
        this.queue.updateItem(fileId, {
          status: ROM_STATUS.ERROR,
          errorMessage: error
        });
        this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Failed forging ROM: ${error}` });
        this.processNextInBatch();
        break;
    }
  }

  analyzeROM(item) {
    if (!this.worker) this.initWorker();
    this.queue.updateItem(item.id, { status: ROM_STATUS.ANALYZING });

    this.worker.postMessage({
      type: 'ANALYZE_FILE',
      payload: {
        fileId: item.id,
        file: item.file
      }
    });
  }

  loadSeedDB(buffer) {
    if (!this.worker) this.initWorker();
    this.worker.postMessage({
      type: 'LOAD_SEEDDB',
      payload: { buffer }
    });
  }

  startBatchForge(options = {}) {
    if (this.queue.getAll().length === 0) {
      this.bus.emit('log', { level: LOG_LEVEL.WARN, text: 'Batch queue is empty. Ingest 3DS ROMs first.' });
      return;
    }

    if (!this.queue.hasPending()) {
      this.queue.resetAllForReforge();
    }

    this.batchOptions = options;
    this.isProcessingBatch = true;
    this.bus.emit('batch:started');
    this.processNextInBatch();
  }

  processSingleItem(id, options = {}) {
    const item = this.queue.getItem(id);
    if (!item || !item.file) return;

    if (!this.worker) this.initWorker();

    this.queue.updateItem(id, {
      status: ROM_STATUS.FORGING,
      progress: 0,
      speedMBs: 0
    });

    this.bus.emit('log', { level: LOG_LEVEL.INFO, text: `Dispatching "${item.name}" to hardware stream worker...` });

    this.worker.postMessage({
      type: 'PROCESS_ROM',
      payload: {
        fileId: item.id,
        file: item.file,
        options: {
          outputFormat: options.outputFormat || 'same',
          suffix: options.suffix || '_decrypted'
        }
      }
    });
  }

  processNextInBatch() {
    if (!this.isProcessingBatch) return;

    const next = this.queue.getNextPending();
    if (!next) {
      this.isProcessingBatch = false;
      this.bus.emit('batch:completed');
      this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: 'All batch queue operations finished!' });
      return;
    }

    this.processSingleItem(next.id, this.batchOptions);
  }
}
