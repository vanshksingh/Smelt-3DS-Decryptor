/**
 * Smelt Next — Dropzone & File Ingestion View
 */

export class DropzoneView {
  constructor(eventBus, dropzoneEl, fileInputEl) {
    this.bus = eventBus;
    this.dropzone = dropzoneEl;
    this.fileInput = fileInputEl;

    this.bindEvents();
  }

  bindEvents() {
    if (!this.dropzone) return;

    ['dragenter', 'dragover'].forEach(name => {
      this.dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.dropzone.classList.add('drag-active');
      });
    });

    ['dragleave', 'drop'].forEach(name => {
      this.dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.dropzone.classList.remove('drag-active');
      });
    });

    this.dropzone.addEventListener('drop', (e) => {
      const files = Array.from(e.dataTransfer.files || []);
      this.emitFiles(files);
    });

    this.dropzone.addEventListener('click', (e) => {
      if (e.target.closest('button') || e.target.closest('label') || e.target.closest('input')) {
        return;
      }
      if (this.fileInput) this.fileInput.click();
    });

    if (this.fileInput) {
      this.fileInput.addEventListener('change', (e) => {
        const files = Array.from(e.target.files || []);
        this.emitFiles(files);
        this.fileInput.value = '';
      });
    }
  }

  emitFiles(files) {
    if (!files || files.length === 0) return;
    this.bus.emit('files:ingested', files);
  }
}
