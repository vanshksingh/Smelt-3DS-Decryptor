/**
 * Smelt Next — Safe Download & Stream Saver Service
 */
import { LOG_LEVEL } from '../core/constants.js';

export class DownloadService {
  constructor(eventBus) {
    this.bus = eventBus;
  }

  downloadBlob(blob, filename) {
    if (!blob) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: 'Download error: Result data is empty.' });
      return;
    }

    try {
      const url = URL.createObjectURL(blob);
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

      this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `Triggered download: "${filename}"` });
    } catch (err) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Download failed: ${err.message}` });
    }
  }
}
