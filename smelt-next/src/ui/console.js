/**
 * Smelt Next — Real-time Forge Console & Telemetry Display
 */

export class ForgeConsole {
  constructor(containerElement, statsElements = {}) {
    this.container = containerElement;
    this.stats = statsElements;
    this.logs = [];
    this.autoScroll = true;
    this.maxLogs = 500;
  }

  log(text, level = 'info') {
    const entry = {
      id: Date.now() + Math.random(),
      timestamp: new Date().toLocaleTimeString(),
      text,
      level
    };

    this.logs.push(entry);
    if (this.logs.length > this.maxLogs) {
      this.logs.shift();
    }

    this.renderEntry(entry);
  }

  renderEntry(entry) {
    if (!this.container) return;

    const row = document.createElement('div');
    row.className = `console-line log-${entry.level}`;

    const badge = document.createElement('span');
    badge.className = `log-badge badge-${entry.level}`;
    badge.textContent = entry.level.toUpperCase();

    const time = document.createElement('span');
    time.className = 'log-time';
    time.textContent = entry.timestamp;

    const msg = document.createElement('span');
    msg.className = 'log-msg';
    msg.textContent = entry.text;

    row.appendChild(time);
    row.appendChild(badge);
    row.appendChild(msg);

    this.container.appendChild(row);

    if (this.autoScroll) {
      this.container.scrollTop = this.container.scrollHeight;
    }
  }

  updateHUD({ speedMBs = 0, etaSeconds = 0, progressPercent = 0, currentTask = 'Idle' }) {
    if (this.stats.speed) {
      this.stats.speed.textContent = `${speedMBs.toFixed(1)} MB/s`;
    }
    if (this.stats.eta) {
      this.stats.eta.textContent = etaSeconds > 0 ? `${etaSeconds}s remaining` : 'Done / Ready';
    }
    if (this.stats.progress) {
      this.stats.progress.style.width = `${progressPercent}%`;
    }
    if (this.stats.task) {
      this.stats.task.textContent = currentTask;
    }
  }

  clear() {
    this.logs = [];
    if (this.container) {
      this.container.innerHTML = '';
    }
  }

  exportLogs() {
    const text = this.logs
      .map(l => `[${l.timestamp}] [${l.level.toUpperCase()}] ${l.text}`)
      .join('\n');
    const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `smelt_next_logs_${Date.now()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  }
}
