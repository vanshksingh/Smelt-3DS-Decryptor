/**
 * Smelt Next — Safe Batch Download & Stream Saver Service
 */
import { LOG_LEVEL } from '../core/constants.js';

export class DownloadService {
  constructor(eventBus) {
    this.bus = eventBus;
    this.queue = [];
    this.isProcessing = false;
  }

  /**
   * Enqueue a file for safe, reliable download without browser dropping/blocking.
   */
  async downloadBlob(blob, filename, userInitiated = false) {
    if (!blob) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: 'Download error: Result data is empty.' });
      return;
    }

    this.queue.push({ blob, filename, userInitiated });
    this.processQueue();
  }

  /**
   * Process download queue sequentially with staggered timing to prevent browser drops.
   */
  async processQueue() {
    if (this.isProcessing || this.queue.length === 0) return;

    this.isProcessing = true;

    while (this.queue.length > 0) {
      const { blob, filename, userInitiated } = this.queue.shift();

      try {
        await this._performDownload(blob, filename, userInitiated);
      } catch (err) {
        this.bus.emit('log', {
          level: LOG_LEVEL.ERROR,
          text: `Failed to save "${filename}": ${err.message}`
        });
      }

      // Staggered delay (600ms) between downloads to ensure all batch files are saved reliably
      if (this.queue.length > 0) {
        await new Promise((resolve) => setTimeout(resolve, 600));
      }
    }

    this.isProcessing = false;
  }

  async _performDownload(blob, filename, userInitiated) {
    const ext = filename.split('.').pop().toLowerCase();

    // 1. If manual user click and File System Access API is supported, offer direct stream save
    if (userInitiated && typeof window !== 'undefined' && window.showSaveFilePicker) {
      try {
        const handle = await window.showSaveFilePicker({
          suggestedName: filename,
          types: [
            {
              description: 'Nintendo 3DS ROM Image',
              accept: {
                'application/octet-stream': [`.${ext}`]
              }
            }
          ]
        });

        const writable = await handle.createWritable();
        if (blob.stream && writable.write) {
          await blob.stream().pipeTo(writable);
        } else {
          await writable.write(blob);
          await writable.close();
        }

        this.bus.emit('log', {
          level: LOG_LEVEL.SUCCESS,
          text: `Saved to disk: "${filename}"`
        });
        return;
      } catch (err) {
        if (err.name === 'AbortError') {
          // User cancelled save dialog
          return;
        }
        console.warn('showSaveFilePicker failed, falling back to direct anchor download:', err);
      }
    }

    // 2. High-reliability Anchor Download (Used for batch auto-saves and standard downloads)
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.style.display = 'none';
    anchor.href = url;
    anchor.download = filename;
    anchor.rel = 'noopener';
    document.body.appendChild(anchor);
    anchor.click();

    this.bus.emit('log', {
      level: LOG_LEVEL.SUCCESS,
      text: `Saved: "${filename}" (${(blob.size / (1024 * 1024)).toFixed(1)} MB)`
    });

    // Clean up object URL after download has started
    setTimeout(() => {
      if (document.body.contains(anchor)) {
        document.body.removeChild(anchor);
      }
      URL.revokeObjectURL(url);
    }, 20000);
  }
}
