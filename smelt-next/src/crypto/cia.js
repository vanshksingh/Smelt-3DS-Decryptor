/**
 * Smelt Next — CIA parser; decrypts embedded NCCH contents
 */
import { NCCHReader, NCCH_MAGIC } from './ncch.js';

export class CIAReader {
  static align64Num(size) {
    return (size + 63) & ~63;
  }

  static tmdBodyOffset(sigType) {
    switch (sigType) {
      case 0x00010000:
      case 0x00010003:
        return 4 + 0x200 + 0x3c;
      case 0x00010001:
      case 0x00010004:
        return 4 + 0x100 + 0x3c;
      case 0x00010005:
        return 4 + 0x3c + 0x40;
      default:
        return 4 + 0x100 + 0x3c;
    }
  }

  static async parseLayout(file) {
    if (file.size < 0x20) return null;
    const view = new DataView(await file.slice(0, 0x20).arrayBuffer());
    const certSize = view.getUint32(8, true);
    const ticketSize = view.getUint32(12, true);
    const tmdSize = view.getUint32(16, true);
    const metaSize = view.getUint32(20, true);
    const contentSize = NCCHReader.readUInt64LE(view, 24);
    const maxHeader = 32 * 1024 * 1024;
    if (certSize > maxHeader || ticketSize > maxHeader || tmdSize > maxHeader) return null;

    const certOffset = this.align64Num(0x20);
    const ticketOffset = this.align64Num(certOffset + certSize);
    const tmdOffset = this.align64Num(ticketOffset + ticketSize);
    const contentOffset = this.align64Num(tmdOffset + tmdSize);
    return {
      headerSize: view.getUint32(0, true),
      certOffset,
      certSize,
      ticketOffset,
      ticketSize,
      tmdOffset,
      tmdSize,
      metaSize,
      contentOffset,
      contentSize: Number(contentSize)
    };
  }

  static async listContents(file, layout) {
    const contents = [];
    const tmdHead = await file.slice(layout.tmdOffset, layout.tmdOffset + Math.min(layout.tmdSize, 64)).arrayBuffer();
    if (tmdHead.byteLength < 4) return contents;

    const sigType = new DataView(tmdHead).getUint32(0, false);
    const bodyOff = this.tmdBodyOffset(sigType);
    const countOff = layout.tmdOffset + bodyOff + 0x9e;
    const recordsOff = layout.tmdOffset + bodyOff + 0x9c4;
    if (countOff + 2 > file.size) return contents;

    const contentCount = new DataView(await file.slice(countOff, countOff + 2).arrayBuffer()).getUint16(0, false);
    if (contentCount <= 0 || contentCount > 1024) return contents;

    const recSize = contentCount * 0x30;
    if (recordsOff + recSize > file.size) return contents;
    const recView = new DataView(await file.slice(recordsOff, recordsOff + recSize).arrayBuffer());

    let cursor = layout.contentOffset;
    for (let i = 0; i < contentCount; i++) {
      const base = i * 0x30;
      const type = recView.getUint16(base + 6, false);
      const size = Number(recView.getBigUint64(base + 8, false));
      contents.push({
        index: recView.getUint16(base + 4, false),
        encrypted: (type & 0x0001) !== 0,
        size,
        offset: cursor
      });
      cursor = this.align64Num(cursor + size);
    }
    return contents;
  }

  static async analyzeCIA(file) {
    const layout = await this.parseLayout(file);
    if (!layout) {
      return { status: 'invalid', message: 'File is too small to be a valid CIA container.' };
    }

    let titleId = '0004000000000000';
    if (layout.tmdOffset + 0x194 <= file.size) {
      const tIdBytes = new Uint8Array(
        await file.slice(layout.tmdOffset + 0x18c, layout.tmdOffset + 0x194).arrayBuffer()
      );
      if (tIdBytes.length === 8) titleId = NCCHReader.bytesToHex(tIdBytes, false);
    }

    let primaryNCCH = null;
    let isClean = false;
    let analysisState = 'decrypt';
    let stateExplanation = 'CIA container detected.';

    if (layout.contentOffset + 0x200 <= file.size) {
      const ncchData = new Uint8Array(
        await file.slice(layout.contentOffset, layout.contentOffset + 0x200).arrayBuffer()
      );
      const ncchView = new DataView(ncchData.buffer, ncchData.byteOffset, ncchData.byteLength);
      if (NCCHReader.readUInt32LE(ncchView, 0x100) === NCCH_MAGIC) {
        const ncch = NCCHReader.parseNCCHHeader(ncchData, layout.contentOffset);
        const probe = new Uint8Array(
          await file.slice(layout.contentOffset + 0x200, layout.contentOffset + 0x210).arrayBuffer()
        );
        const plain = NCCHReader.isPrintableBlock(probe);
        isClean = ncch.noCrypto;
        if (ncch.noCrypto) {
          analysisState = 'clean';
          stateExplanation = 'CIA archive is fully decrypted with NoCrypto flags active.';
        } else if (plain) {
          analysisState = 'patch';
          stateExplanation = 'CIA NCCH is plaintext but missing NoCrypto. Instant header forge.';
        } else {
          analysisState = 'decrypt';
          stateExplanation = 'Encrypted CIA NCCH. Forge will AES-CTR decrypt then set NoCrypto.';
        }
        primaryNCCH = { productCode: ncch.productCode, makerCode: ncch.makerCode, noCrypto: ncch.noCrypto };
      } else {
        analysisState = 'decrypt';
        stateExplanation =
          'CIA content is titlekey-wrapped (no NCCH magic). Decrypt the eShop titlekey layer first.';
      }
    }

    return {
      status: 'valid',
      isCIA: true,
      analysisState,
      titleId,
      productCode: primaryNCCH?.productCode || 'CTR-N-CIA',
      makerCode: primaryNCCH?.makerCode || '00',
      stateExplanation,
      noCrypto: isClean,
      layout,
      primaryNCCH
    };
  }

  static async patchCIA(file, onProgress = () => {}, log = null) {
    const analysis = await this.analyzeCIA(file);
    if (analysis.status !== 'valid' || !analysis.layout) {
      throw new Error('Invalid CIA container.');
    }

    const { contentOffset } = analysis.layout;
    if (contentOffset + 0x200 > file.size) {
      return { resultBlob: file, patchedCount: 0, wasClean: true, decrypted: false };
    }

    const magicView = new DataView(await file.slice(contentOffset, contentOffset + 0x200).arrayBuffer());
    if (NCCHReader.readUInt32LE(magicView, 0x100) !== NCCH_MAGIC) {
      throw new Error(
        'This CIA is still titlekey-encrypted. Smelt Next forges NCCH crypto, not the eShop titlekey layer.'
      );
    }

    const contents = await this.listContents(file, analysis.layout);
    const ncchOffsets = new Set();

    if (contents.length) {
      for (const chunk of contents) {
        if (chunk.encrypted) continue;
        if (chunk.offset + 0x104 > file.size) continue;
        const magicView = new DataView(
          await file.slice(chunk.offset + 0x100, chunk.offset + 0x104).arrayBuffer()
        );
        if (NCCHReader.readUInt32LE(magicView, 0) === NCCH_MAGIC) {
          ncchOffsets.add(chunk.offset);
        }
      }
    } else {
      ncchOffsets.add(contentOffset);
    }

    if (contents.some((c) => c.encrypted) && log) {
      log('Skipping titlekey-encrypted CIA content chunks (TMD type bit 0).', 'warn');
    }

    if (!ncchOffsets.size) {
      throw new Error(
        'No decryptable NCCH content found in CIA. Titlekey-encrypted CIAs need the macOS toolchain (ctrdecrypt).'
      );
    }

    const allPatches = [];
    let patchedCount = 0;
    let decryptedAny = false;
    let bytesDone = 0;
    const hint = Math.max(file.size * 0.85, 1);

    for (const offset of ncchOffsets) {
      const onBytes = (n) => {
        bytesDone += n;
        onProgress(Math.min(95, Math.floor((bytesDone / hint) * 90) + 5));
      };
      const result = await NCCHReader.collectNCCHPatches(file, offset, onBytes, log);
      if (result.patched) {
        allPatches.push(...result.patches);
        patchedCount++;
        if (result.decrypted) decryptedAny = true;
      }
    }

    if (!allPatches.length) {
      onProgress(100);
      return { resultBlob: file, patchedCount: 0, wasClean: true, decrypted: false };
    }

    onProgress(98);
    return {
      resultBlob: NCCHReader.stitchPatches(file, allPatches),
      patchedCount,
      wasClean: false,
      decrypted: decryptedAny
    };
  }
}
