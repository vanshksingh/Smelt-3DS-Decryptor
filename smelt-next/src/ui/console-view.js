/**
 * Smelt Next — Telemetry Console View
 */
export class ConsoleView {
  constructor(eventBus, elements = {}) {
    this.bus = eventBus;
    this.container = elements.container;
    this.speedEl = elements.speed;
    this.etaEl = elements.eta;
    this.taskEl = elements.task;
    this.clearBtn = elements.clearBtn;
    this.exportBtn = elements.exportBtn;

    this.logs = [];
    this.maxLogs = 500;
    this.autoScroll = true;

    this.bindEvents();
    this.subscribeEvents();
    this.appendLog('Smelt Next boot complete. Insert a game card or drop ROM files.', 'success');
  }

  bindEvents() {
    if (this.clearBtn) {
      this.clearBtn.addEventListener('click', () => this.clear());
    }
    if (this.exportBtn) {
      this.exportBtn.addEventListener('click', () => this.exportLogs());
    }
  }

  subscribeEvents() {
    this.bus.on('log', ({ level, text }) => this.appendLog(text, level));
    this.bus.on('telemetry:progress', (data) => this.updateHUD(data));
    this.bus.on('batch:completed', () => {
      this.updateHUD({ speedMBs: 0, etaSeconds: 0 });
      if (this.taskEl) this.taskEl.textContent = 'All tasks completed!';
    });
  }

  appendLog(text, level = 'info') {
    const entry = {
      timestamp: new Date().toLocaleTimeString(),
      text,
      level
    };

    this.logs.push(entry);
    if (this.logs.length > this.maxLogs) {
      this.logs.shift();
    }

    if (!this.container) return;

    const safeLevel = ['info', 'success', 'warn', 'error'].includes(level) ? level : 'info';
    const row = document.createElement('div');
    row.className = `console-line log-${safeLevel}`;

    const time = document.createElement('span');
    time.className = 'log-time';
    time.textContent = entry.timestamp;

    const badge = document.createElement('span');
    badge.className = `log-badge badge-${safeLevel}`;
    badge.textContent = safeLevel.toUpperCase();

    const msg = document.createElement('span');
    msg.className = 'log-msg';
    msg.textContent = text;

    row.appendChild(time);
    row.appendChild(badge);
    row.appendChild(msg);

    this.container.appendChild(row);

    if (this.autoScroll) {
      this.container.scrollTop = this.container.scrollHeight;
    }
  }

  updateHUD({ speedMBs = 0, etaSeconds = 0 }) {
    if (this.speedEl) {
      this.speedEl.textContent = `${Number(speedMBs).toFixed(1)} MB/s`;
    }
    if (this.etaEl) {
      this.etaEl.textContent = etaSeconds > 0 ? `${etaSeconds}s remaining` : 'Ready';
    }
  }

  clear() {
    this.logs = [];
    if (this.container) this.container.innerHTML = '';
  }

  exportLogs() {
    const text = this.logs.map(l => `[${l.timestamp}] [${l.level.toUpperCase()}] ${l.text}`).join('\n');
    const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
    this.bus.emit('request:download', { blob, filename: `smelt_logs_${Date.now()}.txt` });
  }
}
