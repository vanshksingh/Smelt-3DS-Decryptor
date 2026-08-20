/**
 * Smelt Next — CIA (CTR Importable Archive) Parser
 */
import { NCCHReader } from './ncch.js';

export class CIAReader {
  static align64(size) {
    return (size + 63n) & ~63n;
  }

  static align64Num(size) {
    return (size + 63) & ~63;
  }

  /**
   * Analyzes CIA header from initial byte slice
   * @param {Uint8Array} headerData First 1-2MB of CIA file
   * @param {number} fileSize Total file size in bytes
   */
  static analyzeCIA(headerData, fileSize) {
    const data = headerData instanceof Uint8Array ? headerData : new Uint8Array(headerData);
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

    if (data.length < 0x20) {
      return { status: 'invalid', message: 'File is too small to be a valid CIA container.' };
    }

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

    let titleId = '0004000000000000';
    if (data.length >= tmdOffset + 0x194) {
      const tIdBytes = data.slice(tmdOffset + 0x18C, tmdOffset + 0x194);
      titleId = NCCHReader.bytesToHex(tIdBytes, false);
    }

    // Inspect first NCCH partition at contentOffset
    let primaryNCCH = null;
    if (data.length >= contentOffset + 0x200) {
      const ncchSlice = data.slice(contentOffset);
      primaryNCCH = NCCHReader.analyzeContainer(ncchSlice, fileSize - contentOffset);
    }

    return {
      status: 'valid',
      isCIA: true,
      analysisState: 'cia',
      titleId,
      productCode: primaryNCCH?.productCode || 'CTR-N-CIA',
      makerCode: primaryNCCH?.makerCode || '00',
      stateExplanation: 'CIA container detected. Smelt Next will extract content chunks and forge a clean .cci/.3ds container.',
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
}
