/**
 * Smelt Next — Lightweight Typed Event Bus for Loosely Coupled Architecture
 */
export class EventBus {
  constructor() {
    this.listeners = new Map();
  }

  on(event, callback) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event).add(callback);
    return () => this.off(event, callback);
  }

  once(event, callback) {
    const unbind = this.on(event, (...args) => {
      unbind();
      callback(...args);
    });
    return unbind;
  }

  off(event, callback) {
    if (this.listeners.has(event)) {
      this.listeners.get(event).delete(callback);
    }
  }

  emit(event, payload) {
    if (this.listeners.has(event)) {
      for (const callback of this.listeners.get(event)) {
        try {
          callback(payload);
        } catch (err) {
          console.error(`Error in event listener for "${event}":`, err);
        }
      }
    }
  }
}

export const globalEventBus = new EventBus();
