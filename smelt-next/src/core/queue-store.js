/**
 * Smelt Next — Observable Queue State Store
 */
import { ROM_STATUS } from './constants.js';

export class QueueStore {
  constructor(eventBus) {
    this.bus = eventBus;
    this.items = new Map(); // id -> item
  }

  addItem(file) {
    const id = 'rom_' + Math.random().toString(36).substring(2, 11) + '_' + Date.now();
    const item = {
      id,
      file,
      name: file.name,
      size: file.size,
      status: ROM_STATUS.QUEUED,
      progress: 0,
      speedMBs: 0,
      analysis: null,
      resultBlob: null,
      finalFilename: null,
      errorMessage: null
    };

    this.items.set(id, item);
    this.bus.emit('queue:item-added', item);
    this.bus.emit('queue:updated', this.getAll());
    return item;
  }

  getItem(id) {
    return this.items.get(id) || null;
  }

  getAll() {
    return Array.from(this.items.values());
  }

  hasPending() {
    return this.getAll().some(
      i => i.status === ROM_STATUS.READY || i.status === ROM_STATUS.QUEUED || i.status === ROM_STATUS.ANALYZING
    );
  }

  getNextPending() {
    return this.getAll().find(
      i => i.status === ROM_STATUS.READY || i.status === ROM_STATUS.QUEUED
    ) || null;
  }

  updateItem(id, updates) {
    const item = this.items.get(id);
    if (!item) return;

    Object.assign(item, updates);
    this.bus.emit('queue:item-updated', item);
    this.bus.emit('queue:updated', this.getAll());
  }

  removeItem(id) {
    if (this.items.has(id)) {
      this.items.delete(id);
      this.bus.emit('queue:item-removed', id);
      this.bus.emit('queue:updated', this.getAll());
    }
  }

  clear() {
    this.items.clear();
    this.bus.emit('queue:cleared');
    this.bus.emit('queue:updated', []);
  }

  resetAllForReforge() {
    for (const item of this.items.values()) {
      item.status = ROM_STATUS.READY;
      item.progress = 0;
      item.speedMBs = 0;
      item.resultBlob = null;
      item.errorMessage = null;
      this.bus.emit('queue:item-updated', item);
    }
    this.bus.emit('queue:updated', this.getAll());
  }
}
