/**
 * Smelt Next — Background decryption worker
 */

import { NCCHReader } from '../crypto/ncch.js';
import { CIAReader } from '../crypto/cia.js';
import { GlobalKeyManager } from '../crypto/keys.js';

self.onmessage = async (e) => {
  const { type, payload } = e.data;
  try {
    switch (type) {
      case 'LOAD_SEEDDB': {
        const count = GlobalKeyManager.loadSeedDB(payload.buffer);
        self.postMessage({ type: 'SEEDDB_LOADED', count });
        break;
      }
      case 'ANALYZE_FILE': {
        const { fileId, file } = payload;
        const ext = file.name.split('.').pop().toLowerCase();
        const analysis = ext === 'cia'
          ? await CIAReader.analyzeCIA(file)
          : await NCCHReader.analyzeFile(file);
        self.postMessage({
          type: 'ANALYSIS_COMPLETE',
          fileId,
          analysis: { ...analysis, fileName: file.name, fileSize: file.size, fileType: ext }
        });
        break;
      }
      case 'PROCESS_ROM':
        await handleRomProcessing(payload);
        break;
      default:
        self.postMessage({
          type: 'PROCESS_ERROR',
          fileId: payload?.fileId,
          error: `Unknown worker action: ${type}`
        });
    }
  } catch (err) {
    self.postMessage({
      type: 'PROCESS_ERROR',
      fileId: payload?.fileId,
      error: err.message || String(err)
    });
  }
};

async function handleRomProcessing({ fileId, file, options = {} }) {
  const startTime = Date.now();
  const totalBytes = file.size;
  const ext = file.name.split('.').pop().toLowerCase();

  const log = (text, level = 'info') => {
    self.postMessage({ type: 'LOG', fileId, level, text });
  };

  const reportProgress = (percent) => {
    const elapsedSec = Math.max((Date.now() - startTime) / 1000, 0.01);
    const processed = Math.floor((percent / 100) * totalBytes);
    const remaining = Math.max(0, 100 - percent);
    self.postMessage({
      type: 'PROGRESS',
      fileId,
      percent,
      speedMBs: Number(((processed / (1024 * 1024)) / elapsedSec).toFixed(1)),
      etaSeconds: percent > 5 ? Math.round((elapsedSec / percent) * remaining) : 0,
      processedBytes: processed,
      totalBytes
    });
  };

  log(`Forge start: "${file.name}" (${(file.size / (1024 * 1024)).toFixed(1)} MB)`);

  const baseName = file.name.replace(/\.[^/.]+$/, '');
  let targetExt = ext;
  if (options.outputFormat === '3ds') targetExt = ext === 'cia' ? 'cia' : '3ds';
  else if (options.outputFormat === 'cci') targetExt = ext === 'cia' ? 'cia' : 'cci';
  const suffix = options.suffix || '_decrypted';
  const finalFilename = `${baseName}${suffix}.${targetExt}`;

  reportProgress(4);

  const patchResult = ext === 'cia'
    ? await CIAReader.patchCIA(file, reportProgress, log)
    : await NCCHReader.patchAllPartitions(file, reportProgress, log);

  reportProgress(100);
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
  const sizeMB = (file.size / (1024 * 1024)).toFixed(1);

  if (patchResult.wasClean) {
    log(`Already clean (NoCrypto set). ${sizeMB} MB ready in ${elapsed}s.`, 'success');
  } else if (patchResult.decrypted) {
    log(`Decrypted + forged NoCrypto on ${patchResult.patchedCount} NCCH partition(s) in ${elapsed}s.`, 'success');
  } else {
    log(`Set NoCrypto on ${patchResult.patchedCount} partition(s) in ${elapsed}s (plaintext dump).`, 'success');
  }

  if (ext === 'cia') log('Citra/Lime3DS: File → Install CIA… (do not File → Open a .cia).');
  else log('Ready for Citra / Lime3DS / Azahar via File → Open.');

  self.postMessage({
    type: 'PROCESS_COMPLETE',
    fileId,
    resultBlob: patchResult.resultBlob,
    finalFilename,
    analysisState: patchResult.wasClean ? 'clean' : patchResult.decrypted ? 'decrypt' : 'patch'
  });
}
