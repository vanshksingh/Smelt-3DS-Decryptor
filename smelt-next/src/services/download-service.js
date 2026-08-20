/**
 * Smelt Next — Safe Download & Stream Saver Service
 */
import { LOG_LEVEL } from '../core/constants.js';

export class DownloadService {
  constructor(eventBus) {
    this.bus = eventBus;
  }

  async downloadBlob(blob, filename) {
    if (!blob) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: 'Download error: Result data is empty.' });
      return;
    }

    try {
      if (window.showSaveFilePicker) {
        try {
          const handle = await window.showSaveFilePicker({ suggestedName: filename });
          const writable = await handle.createWritable();
          await writable.write(blob);
          await writable.close();
          this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `Successfully saved: "${filename}" to disk.` });
          return;
        } catch (err) {
          if (err.name === 'AbortError') return; // User cancelled
          console.warn('showSaveFilePicker failed, falling back to anchor download', err);
        }
      }

      // Fallback for Safari / Firefox
      // Ensure the Blob has the correct octet-stream type to force download
      const downloadBlob = new Blob([blob], { type: 'application/octet-stream' });
      const url = URL.createObjectURL(downloadBlob);
      const anchor = document.createElement('a');
      anchor.style.display = 'none';
      anchor.href = url;
      anchor.download = filename;
      document.body.appendChild(anchor);
      anchor.click();

      setTimeout(() => {
        document.body.removeChild(anchor);
        URL.revokeObjectURL(url);
      }, 10000);

      this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `Triggered fallback download: "${filename}"` });
    } catch (err) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Download failed: ${err.message}` });
    }
  }
}
