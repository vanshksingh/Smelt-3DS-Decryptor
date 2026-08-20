/**
 * Smelt Next — High Performance Background Decryption Worker
 */

import { NCCHReader } from '../crypto/ncch.js?v=20260821_02';
import { CIAReader } from '../crypto/cia.js?v=20260821_02';
import { KeyManager } from '../crypto/keys.js?v=20260821_02';

const keyManager = new KeyManager();

self.onmessage = async (e) => {
  const { type, payload } = e.data;

  try {
    switch (type) {
      case 'LOAD_SEEDDB': {
        const count = keyManager.loadSeedDB(payload.buffer);
        self.postMessage({ type: 'SEEDDB_LOADED', count });
        break;
      }

      case 'ANALYZE_FILE': {
        const { fileId, file } = payload;
        const ext = file.name.split('.').pop().toLowerCase();

        let analysis;
        if (ext === 'cia') {
          analysis = await CIAReader.analyzeCIA(file);
        } else {
          analysis = await NCCHReader.analyzeFile(file);
        }

        self.postMessage({
          type: 'ANALYSIS_COMPLETE',
          fileId,
          analysis: {
            ...analysis,
            fileName: file.name,
            fileSize: file.size,
            fileType: ext
          }
        });
        break;
      }

      case 'PROCESS_ROM': {
        await handleRomProcessing(payload);
        break;
      }

      default:
        console.warn('Unknown worker action:', type);
    }
  } catch (err) {
    self.postMessage({
      type: 'PROCESS_ERROR',
      fileId: payload?.fileId,
      error: err.message || String(err)
    });
  }
};

/**
 * Handles instant header patching and partition processing
 */
async function handleRomProcessing({ fileId, file, options }) {
  const startTime = Date.now();
  const totalBytes = file.size;
  const ext = file.name.split('.').pop().toLowerCase();

  const log = (text, level = 'info') => {
    self.postMessage({
      type: 'LOG',
      fileId,
      level,
      text: `[${new Date().toLocaleTimeString()}] ${text}`
    });
  };

  const reportProgress = (percent) => {
    const now = Date.now();
    const elapsedSec = Math.max((now - startTime) / 1000, 0.01);
    const processed = Math.floor((percent / 100) * totalBytes);
    const speedMBs = (processed / (1024 * 1024)) / elapsedSec;

    self.postMessage({
      type: 'PROGRESS',
      fileId,
      percent,
      speedMBs: Number(speedMBs.toFixed(1)),
      etaSeconds: 0,
      processedBytes: processed,
      totalBytes
    });
  };

  log(`Beginning Forge pipeline for "${file.name}" (${(file.size / (1024 * 1024)).toFixed(1)} MB)...`);

  // Target filename and extension
  const baseName = file.name.replace(/\.[^/.]+$/, '');
  let targetExt = ext;
  if (options.outputFormat === '3ds') {
    targetExt = '3ds';
  } else if (options.outputFormat === 'cci') {
    targetExt = ext === 'cia' ? 'cia' : 'cci';
  }
  const finalFilename = `${baseName}_decrypted.${targetExt}`;

  reportProgress(10);

  let patchResult;
  if (ext === 'cia') {
    log('Scanning CIA container headers and embedded NCCH partitions...');
    patchResult = await CIAReader.patchCIA(file, (p) => reportProgress(10 + Math.floor(p * 0.8)));
  } else {
    log('Scanning NCSD cartridge table & NCCH partition headers across all sectors...');
    patchResult = await NCCHReader.patchAllPartitions(file, (p) => reportProgress(10 + Math.floor(p * 0.8)));
  }

  reportProgress(100);

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
  const sizeMB = (file.size / (1024 * 1024)).toFixed(1);

  if (patchResult.wasClean) {
    log(`ROM is already fully clean/decrypted (${sizeMB} MB). Output prepared in ${elapsed}s.`, 'success');
  } else {
    log(`Forged NoCrypto flag on ${patchResult.patchedCount} partition(s) successfully in ${elapsed}s!`, 'success');
  }

  self.postMessage({
    type: 'PROCESS_COMPLETE',
    fileId,
    resultBlob: patchResult.resultBlob,
    finalFilename,
    analysisState: patchResult.wasClean ? 'clean' : 'patch'
  });
}
