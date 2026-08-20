/**
 * Smelt Next — CIA (CTR Importable Archive) Parser & Patcher
 */
import { NCCHReader, NCCH_MAGIC } from './ncch.js';

export class CIAReader {
  static align64(size) {
    return (size + 63n) & ~63n;
  }

  static align64Num(size) {
    return (size + 63) & ~63;
  }

  /**
   * Analyzes CIA file structure directly from File object
   * @param {File|Blob} file 
   */
  static async analyzeCIA(file) {
    const fileSize = file.size;
    if (fileSize < 0x20) {
      return { status: 'invalid', message: 'File is too small to be a valid CIA container.' };
    }

    const headBuf = await file.slice(0, 0x20).arrayBuffer();
    const view = new DataView(headBuf);

    const headerSize = view.getUint32(0, true);
    const type = view.getUint16(4, true);
    const version = view.getUint16(6, true);
    const certSize = view.getUint32(8, true);
    const ticketSize = view.getUint32(12, true);
    const tmdSize = view.getUint32(16, true);
    const metaSize = view.getUint32(20, true);
    const contentSize = NCCHReader.readUInt64LE(view, 24);

    const maxHeader = 32 * 1024 * 1024;
    if (certSize > maxHeader || ticketSize > maxHeader || tmdSize > maxHeader) {
      return { status: 'invalid', message: 'CIA header fields exceed maximum limits.' };
    }

    const certOffset = this.align64Num(0x20);
    const ticketOffset = this.align64Num(certOffset + certSize);
    const tmdOffset = this.align64Num(ticketOffset + ticketSize);
    const contentOffset = this.align64Num(tmdOffset + tmdSize);

    // Extract TitleID from TMD
    let titleId = '0004000000000000';
    if (tmdOffset + 0x194 <= fileSize) {
      const tmdBuf = await file.slice(tmdOffset + 0x18C, tmdOffset + 0x194).arrayBuffer();
      const tIdBytes = new Uint8Array(tmdBuf);
      if (tIdBytes.length === 8) {
        titleId = NCCHReader.bytesToHex(tIdBytes, false);
      }
    }

    // Inspect primary NCCH content at contentOffset
    let primaryNCCH = null;
    let isClean = false;
    let needsPatch = true;

    if (contentOffset + 0x200 <= fileSize) {
      const ncchBuf = await file.slice(contentOffset, contentOffset + 0x200).arrayBuffer();
      const ncchData = new Uint8Array(ncchBuf);
      const ncchView = new DataView(ncchBuf);

      if (NCCHReader.readUInt32LE(ncchView, 0x100) === NCCH_MAGIC) {
        const flags = ncchData.slice(0x188, 0x190);
        const noCrypto = (flags[7] & 0x04) !== 0;
        if (noCrypto) {
          isClean = true;
          needsPatch = false;
        }

        const productBytes = ncchData.slice(0x150, 0x160);
        const productCode = NCCHReader.bytesToAscii(productBytes) || 'CTR-N-CIA';
        const makerBytes = ncchData.slice(0x110, 0x112);
        const makerCode = NCCHReader.bytesToAscii(makerBytes) || '00';

        primaryNCCH = {
          productCode,
          makerCode,
          noCrypto
        };
      }
    }

    return {
      status: 'valid',
      isCIA: true,
      analysisState: isClean ? 'clean' : 'patch',
      titleId,
      productCode: primaryNCCH?.productCode || 'CTR-N-CIA',
      makerCode: primaryNCCH?.makerCode || '00',
      stateExplanation: isClean 
        ? 'CIA archive is fully decrypted with NoCrypto flags active.'
        : 'CIA container detected. Instant header forge ready to patch NoCrypto flag.',
      layout: {
        headerSize,
        certOffset,
        certSize,
        ticketOffset,
        ticketSize,
        tmdOffset,
        tmdSize,
        metaSize,
        contentOffset,
        contentSize: Number(contentSize)
      },
      primaryNCCH
    };
  }

  /**
   * Patches the NoCrypto flag inside the embedded NCCH partitions of a CIA container
   * @param {File|Blob} file 
   * @param {Function} onProgress 
   */
  static async patchCIA(file, onProgress = () => {}) {
    const analysis = await this.analyzeCIA(file);
    if (analysis.status !== 'valid' || !analysis.layout) {
      throw new Error('Invalid CIA container.');
    }

    const { contentOffset } = analysis.layout;
    const fileSize = file.size;

    if (contentOffset + 0x200 > fileSize) {
      return { resultBlob: file, patchedCount: 0, wasClean: true };
    }

    const ncchBuf = await file.slice(contentOffset, contentOffset + 0x200).arrayBuffer();
    const ncchData = new Uint8Array(ncchBuf);
    const ncchView = new DataView(ncchBuf);

    if (NCCHReader.readUInt32LE(ncchView, 0x100) !== NCCH_MAGIC) {
      return { resultBlob: file, patchedCount: 0, wasClean: true };
    }

    const flags = ncchData.slice(0x188, 0x190);
    if ((flags[7] & 0x04) !== 0) {
      // Already clean
      onProgress(100);
      return { resultBlob: file, patchedCount: 0, wasClean: true };
    }

    const patchedFlags = new Uint8Array(flags);
    patchedFlags[7] |= 0x04;

    const flagOffset = contentOffset + 0x188;
    const blobParts = [
      file.slice(0, flagOffset),
      patchedFlags,
      file.slice(flagOffset + patchedFlags.length, fileSize)
    ];

    onProgress(100);
    const resultBlob = new Blob(blobParts, { type: 'application/octet-stream' });
    return { resultBlob, patchedCount: 1, wasClean: false };
  }
}
