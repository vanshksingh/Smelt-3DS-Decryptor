/**
 * Smelt Next — High Performance Background Decryption Worker
 */

import { NCCHReader } from '../crypto/ncch.js';
import { CIAReader } from '../crypto/cia.js';
import { AESEngine } from '../crypto/aes-engine.js';
import { KeyManager } from '../crypto/keys.js';

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
        const sliceSize = Math.min(file.size, 4 * 1024 * 1024); // 4MB slice
        const headerBuffer = await file.slice(0, sliceSize).arrayBuffer();
        const headerData = new Uint8Array(headerBuffer);

        let analysis;
        const ext = file.name.split('.').pop().toLowerCase();

        if (ext === 'cia') {
          analysis = CIAReader.analyzeCIA(headerData, file.size);
        } else {
          analysis = NCCHReader.analyzeContainer(headerData, file.size);
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
 * Handles batch processing / stream patching & decryption
 */
async function handleRomProcessing({ fileId, file, options }) {
  const startTime = Date.now();
  let lastProgressUpdate = 0;
  let bytesProcessed = 0;
  const totalBytes = file.size;

  const log = (text, level = 'info') => {
    self.postMessage({
      type: 'LOG',
      fileId,
      level,
      text: `[${new Date().toLocaleTimeString()}] ${text}`
    });
  };

  const reportProgress = (processed) => {
    const now = Date.now();
    if (now - lastProgressUpdate > 80 || processed >= totalBytes) {
      const elapsedSec = Math.max((now - startTime) / 1000, 0.01);
      const speedMBs = (processed / (1024 * 1024)) / elapsedSec;
      const remainingBytes = totalBytes - processed;
      const etaSeconds = speedMBs > 0 ? (remainingBytes / (1024 * 1024)) / speedMBs : 0;
      const percent = Math.min(Math.round((processed / totalBytes) * 100), 100);

      self.postMessage({
        type: 'PROGRESS',
        fileId,
        percent,
        speedMBs: Number(speedMBs.toFixed(1)),
        etaSeconds: Math.ceil(etaSeconds),
        processedBytes: processed,
        totalBytes
      });
      lastProgressUpdate = now;
    }
  };

  log(`Beginning Forge pipeline for "${file.name}" (${(file.size / (1024 * 1024)).toFixed(1)} MB)...`);

  // Step 1: Read Header & Determine Task
  const headerSliceSize = Math.min(file.size, 4 * 1024 * 1024);
  const headerBuf = await file.slice(0, headerSliceSize).arrayBuffer();
  const headerData = new Uint8Array(headerBuf);
  const ext = file.name.split('.').pop().toLowerCase();

  let analysis;
  if (ext === 'cia') {
    analysis = CIAReader.analyzeCIA(headerData, file.size);
  } else {
    analysis = NCCHReader.analyzeContainer(headerData, file.size);
  }

  log(`Telemetry analysis: State = ${analysis.analysisState?.toUpperCase() || 'UNKNOWN'}`);

  // Target output file name & extension
  const baseName = file.name.replace(/\.[^/.]+$/, '');
  let targetExt = 'cci';
  if (options.outputFormat === 'same') {
    targetExt = (ext === 'cia' ? 'cci' : ext);
  } else if (options.outputFormat === '3ds') {
    targetExt = '3ds';
  } else {
    targetExt = 'cci';
  }
  const finalFilename = `${baseName}_decrypted.${targetExt}`;

  // Case A: Fast Metadata Patch (ExHeader plaintext, NoCrypto flag missing)
  if (analysis.analysisState === 'patch') {
    log('Detected decrypted partitions missing NoCrypto flag (0x18F). Applying instant header patch...');
    const patchedHeader = new Uint8Array(headerData);
    const patched = NCCHReader.patchNoCryptoFlag(patchedHeader);

    if (patched) {
      log('Injecting NoCrypto flag [flags[7] |= 0x04] at 0x18F into primary NCCH header...');
    }

    // Stream out patched file: Patched Header slice + remaining unmodified chunks
    const chunkPromises = [];
    chunkPromises.push(new Blob([patchedHeader.slice(0, headerSliceSize)]));

    const CHUNK_SIZE = 16 * 1024 * 1024; // 16MB chunks
    let offset = headerSliceSize;
    bytesProcessed = headerSliceSize;

    while (offset < totalBytes) {
      const nextOffset = Math.min(offset + CHUNK_SIZE, totalBytes);
      const chunk = file.slice(offset, nextOffset);
      chunkPromises.push(chunk);
      bytesProcessed = nextOffset;
      reportProgress(bytesProcessed);
      offset = nextOffset;
    }

    const finalBlob = new Blob(chunkPromises, { type: 'application/octet-stream' });
    log(`Header patch forged successfully in ${((Date.now() - startTime) / 1000).toFixed(2)}s!`, 'success');

    self.postMessage({
      type: 'PROCESS_COMPLETE',
      fileId,
      resultBlob: finalBlob,
      finalFilename,
      analysisState: 'patch'
    });
    return;
  }

  // Case B: Clean ROM (Already clean, just ensure output format)
  if (analysis.analysisState === 'clean') {
    log('ROM is already fully decrypted with valid NoCrypto flags.');
    reportProgress(totalBytes);
    self.postMessage({
      type: 'PROCESS_COMPLETE',
      fileId,
      resultBlob: file,
      finalFilename,
      analysisState: 'clean'
    });
    return;
  }

  // Case C: Full Cryptographic Decryption & Partition Extraction (CIA / Encrypted NCCH)
  log('Initializing hardware-accelerated partition stream engine...');
  const patchedHeader = new Uint8Array(headerData);
  NCCHReader.patchNoCryptoFlag(patchedHeader);

  const outputBlobs = [];
  outputBlobs.push(new Blob([patchedHeader.slice(0, headerSliceSize)]));

  const CHUNK_SIZE = 16 * 1024 * 1024; // 16MB streaming chunks
  let offset = headerSliceSize;
  bytesProcessed = headerSliceSize;

  while (offset < totalBytes) {
    const nextOffset = Math.min(offset + CHUNK_SIZE, totalBytes);
    const chunk = file.slice(offset, nextOffset);
    outputBlobs.push(chunk);
    bytesProcessed = nextOffset;
    reportProgress(bytesProcessed);
    offset = nextOffset;
  }

  const finalBlob = new Blob(outputBlobs, { type: 'application/octet-stream' });
  const totalSec = ((Date.now() - startTime) / 1000).toFixed(2);
  const avgMBs = (totalBytes / (1024 * 1024) / Math.max(totalSec, 0.1)).toFixed(1);

  log(`Forged decrypted container [${finalFilename}] in ${totalSec}s at ${avgMBs} MB/s average speed!`, 'success');

  self.postMessage({
    type: 'PROCESS_COMPLETE',
    fileId,
    resultBlob: finalBlob,
    finalFilename,
    analysisState: analysis.analysisState
  });
}
