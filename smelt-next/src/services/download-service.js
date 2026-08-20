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

    const ext = filename.split('.').pop().toLowerCase();

    // 1. Modern Chromium File System Access API (Stream directly to disk without memory limits)
    if (typeof window !== 'undefined' && window.showSaveFilePicker) {
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

        this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `Successfully saved: "${filename}" to disk.` });
        return;
      } catch (err) {
        if (err.name === 'AbortError') {
          // User cancelled save dialog
          return;
        }
        console.warn('showSaveFilePicker stream save failed, falling back to anchor download:', err);
      }
    }

    // 2. Standard / Safari Anchor Download
    try {
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.style.display = 'none';
      anchor.href = url;
      anchor.download = filename;
      anchor.rel = 'noopener';
      document.body.appendChild(anchor);
      anchor.click();

      setTimeout(() => {
        if (document.body.contains(anchor)) {
          document.body.removeChild(anchor);
        }
        URL.revokeObjectURL(url);
      }, 15000);

      this.bus.emit('log', { level: LOG_LEVEL.SUCCESS, text: `Downloading: "${filename}"` });
    } catch (err) {
      this.bus.emit('log', { level: LOG_LEVEL.ERROR, text: `Download failed: ${err.message}` });
    }
  }
}
