/**
 * Smelt Next — NCCH / NCSD parser + AES-CTR decrypt + NoCrypto forge
 */

import { GlobalKeyManager, KeyManager } from './keys.js';
import { AESEngine } from './aes-engine.js';

export const NCCH_MAGIC = 0x4843434e;
export const NCSD_MAGIC = 0x4453434e;

const FLAG_FIXED_CRYPTO = 0x01;
const FLAG_NO_CRYPTO = 0x04;
const FLAG_SEED_CRYPTO = 0x20;

const SECTION_EXHEADER = 1;
const SECTION_EXEFS = 2;
const SECTION_ROMFS = 3;

export class NCCHReader {
  static readUInt32LE(buffer, offset = 0) {
    if (buffer instanceof DataView) return buffer.getUint32(offset, true);
    return (
      (buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24)) >>> 0
    );
  }

  static readUInt64LE(buffer, offset = 0) {
    if (buffer instanceof DataView) return buffer.getBigUint64(offset, true);
    const low = BigInt(this.readUInt32LE(buffer, offset));
    const high = BigInt(this.readUInt32LE(buffer, offset + 4));
    return (high << 32n) | low;
  }

  static bytesToHex(bytes, reverse = false) {
    const arr = reverse ? Array.from(bytes).reverse() : Array.from(bytes);
    return arr.map((b) => b.toString(16).padStart(2, '0').toUpperCase()).join('');
  }

  static bytesToAscii(bytes) {
    let str = '';
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 0) break;
      if (bytes[i] >= 32 && bytes[i] <= 126) str += String.fromCharCode(bytes[i]);
    }
    return str.trim();
  }

  static isPrintableBlock(bytes) {
    if (!bytes || !bytes.length) return false;
    let n = 0;
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i];
      if ((b >= 0x20 && b < 0x7f) || b === 0) n++;
    }
    return n / bytes.length >= 0.85;
  }

  static isValidRomFSMagic(bytes) {
    return (
      bytes.length >= 4 &&
      bytes[0] === 0x49 &&
      bytes[1] === 0x56 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x43
    );
  }

  static isValidExeFSHeader(bytes) {
    if (!bytes || bytes.length < 0x80) return false;
    for (let slot = 0; slot < 8; slot++) {
      const nameOff = slot * 16;
      let hasChar = false;
      let validName = true;
      for (let i = 0; i < 8; i++) {
        const c = bytes[nameOff + i];
        if (c === 0) break;
        if (c < 0x20 || c > 0x7e) {
          validName = false;
          break;
        }
        hasChar = true;
      }
      if (hasChar && validName) return true;
    }
    return false;
  }

  static async ncchSectionsLookPlain(file, ncch, ncchOffset) {
    const fileSize = file.size;

    if (ncch.exHeaderSize > 0) {
      if (ncchOffset + 0x210 > fileSize) return false;
      const probe = new Uint8Array(
        await file.slice(ncchOffset + 0x200, ncchOffset + 0x210).arrayBuffer()
      );
      if (!this.isPrintableBlock(probe)) return false;
    }

    if (ncch.exeFsSize > 0) {
      const exeFsStart = ncchOffset + ncch.exeFsOffset;
      if (exeFsStart + 0x200 > fileSize) return false;
      const probe = new Uint8Array(
        await file.slice(exeFsStart, exeFsStart + 0x200).arrayBuffer()
      );
      if (!this.isValidExeFSHeader(probe)) return false;
    }

    if (ncch.romFsSize > 0) {
      const romFsStart = ncchOffset + ncch.romFsOffset;
      if (romFsStart + 4 > fileSize) return false;
      const probe = new Uint8Array(
        await file.slice(romFsStart, romFsStart + 4).arrayBuffer()
      );
      if (!this.isValidRomFSMagic(probe)) return false;
    }

    return true;
  }

  static parseFlags(flagBytes, ncchVersion = 0) {
    const cryptoMethod = flagBytes[2];
    const blockSizeLog = Math.min(flagBytes[6] || 0, 16);
    const mediaUnit = ncchVersion === 1 ? 1 : 512 << blockSizeLog;
    return {
      cryptoMethod,
      blockSizeLog,
      mediaUnit,
      noCrypto: (flagBytes[7] & FLAG_NO_CRYPTO) !== 0,
      fixedCrypto: (flagBytes[7] & FLAG_FIXED_CRYPTO) !== 0,
      seedCrypto: (flagBytes[7] & FLAG_SEED_CRYPTO) !== 0
    };
  }

  static parseNCCHHeader(headerBytes, containerOffset = 0) {
    if (headerBytes.length < 0x200) return null;
    const view = new DataView(headerBytes.buffer, headerBytes.byteOffset, headerBytes.byteLength);
    if (this.readUInt32LE(view, 0x100) !== NCCH_MAGIC) return null;

    const version = headerBytes[0x112] | (headerBytes[0x113] << 8);
    const flags = headerBytes.slice(0x188, 0x190);
    const parsed = this.parseFlags(flags, version);
    const { mediaUnit } = parsed;
    const exHeaderSizeField = this.readUInt32LE(view, 0x180);

    // ExHeader @ +0x200; encrypted block = ExHeader + AccessDesc (0x400 + 0x400)
    const exHeaderSize = exHeaderSizeField > 0 ? 0x800 : 0;
    const exeFsOffset = this.readUInt32LE(view, 0x1a0) * mediaUnit;
    const exeFsSize = this.readUInt32LE(view, 0x1a4) * mediaUnit;
    const romFsOffset = this.readUInt32LE(view, 0x1b0) * mediaUnit;
    const romFsSize = this.readUInt32LE(view, 0x1b4) * mediaUnit;

    return {
      containerOffset,
      keyY: headerBytes.slice(0, 0x10),
      partitionId: headerBytes.slice(0x108, 0x110),
      programId: headerBytes.slice(0x118, 0x120),
      titleId: this.bytesToHex(headerBytes.slice(0x118, 0x120), true),
      productCode: this.bytesToAscii(headerBytes.slice(0x150, 0x160)) || 'CTR-N-3DS',
      makerCode: this.bytesToAscii(headerBytes.slice(0x110, 0x112)) || '00',
      version,
      flags,
      ...parsed,
      exHeaderOffset: 0x200,
      exHeaderSize,
      exeFsOffset,
      exeFsSize,
      romFsOffset,
      romFsSize
    };
  }

  /**
   * Build non-overlapping decrypt regions inside one NCCH partition.
   */
  static buildDecryptSections(ncch, fileSize) {
    const base = ncch.containerOffset;
    const clamp = (offset, size) => {
      if (size <= 0 || offset >= fileSize) return null;
      const end = Math.min(offset + size, fileSize);
      const len = end - offset;
      return len > 0 ? { offset, size: len } : null;
    };

    const raw = [];

    if (ncch.exHeaderSize > 0) {
      const r = clamp(base + ncch.exHeaderOffset, ncch.exHeaderSize);
      if (r) {
        raw.push({
          ...r,
          kind: 'exheader',
          sectionType: SECTION_EXHEADER,
          sectionOffsetBytes: 0,
          absoluteRegionOffset: ncch.exHeaderOffset,
          usePrimaryKey: true
        });
      }
    }

    if (ncch.exeFsSize > 0) {
      const r = clamp(base + ncch.exeFsOffset, ncch.exeFsSize);
      if (r) {
        raw.push({
          ...r,
          kind: 'exefs',
          sectionType: SECTION_EXEFS,
          sectionOffsetBytes: 0,
          absoluteRegionOffset: ncch.exeFsOffset,
          usePrimaryKey: true,
          splitAt: 0x200
        });
      }
    }

    if (ncch.romFsSize > 0) {
      const r = clamp(base + ncch.romFsOffset, ncch.romFsSize);
      if (r) {
        raw.push({
          ...r,
          kind: 'romfs',
          sectionType: SECTION_ROMFS,
          sectionOffsetBytes: 0,
          absoluteRegionOffset: ncch.romFsOffset,
          usePrimaryKey: false
        });
      }
    }

    raw.sort((a, b) => a.offset - b.offset);

    const sections = [];
    for (const sec of raw) {
      if (!sections.length) {
        sections.push(sec);
        continue;
      }
      const prev = sections[sections.length - 1];
      const prevEnd = prev.offset + prev.size;
      if (sec.offset >= prevEnd) {
        sections.push(sec);
        continue;
      }
      if (sec.offset + sec.size <= prevEnd) continue;
      const trim = prevEnd - sec.offset;
      const trimmed = {
        ...sec,
        offset: prevEnd,
        size: sec.size - trim,
        sectionOffsetBytes: sec.sectionOffsetBytes + trim
      };
      if (trimmed.splitAt != null) {
        trimmed.splitAt = Math.max(0, trimmed.splitAt - trim);
      }
      sections.push(trimmed);
    }

    return sections;
  }

  static async analyzeFile(file) {
    const fileSize = file.size;
    if (fileSize < 0x200) {
      return { status: 'invalid', message: 'File is too small to be a valid 3DS container.' };
    }

    const headerBuf = await file.slice(0, 0x200).arrayBuffer();
    const view = new DataView(headerBuf);
    const magic0x100 = this.readUInt32LE(view, 0x100);
    const isNCSD = magic0x100 === NCSD_MAGIC;
    const partitions = [];
    let partition0Offset = 0;

    if (isNCSD) {
      for (let p = 0; p < 8; p++) {
        const offsetSectors = this.readUInt32LE(view, 0x120 + p * 8);
        const lengthSectors = this.readUInt32LE(view, 0x120 + p * 8 + 4);
        if (offsetSectors > 0 && lengthSectors > 0) {
          partitions.push({
            index: p,
            offsetSectors,
            lengthSectors,
            byteOffset: offsetSectors * 0x200,
            byteLength: lengthSectors * 0x200
          });
        }
      }
      if (partitions.length) partition0Offset = partitions[0].byteOffset;
    } else {
      partitions.push({
        index: 0,
        offsetSectors: 0,
        lengthSectors: Math.floor(fileSize / 512),
        byteOffset: 0,
        byteLength: fileSize
      });
    }

    const p0Data = new Uint8Array(await file.slice(partition0Offset, partition0Offset + 0x200).arrayBuffer());
    const ncch = this.parseNCCHHeader(p0Data, partition0Offset);
    if (!ncch) {
      return { status: 'invalid', message: 'Missing valid NCCH signature in primary partition.' };
    }

    let isPlain = ncch.noCrypto;
    if (!isPlain) {
      isPlain = await this.ncchSectionsLookPlain(file, ncch, partition0Offset);
    }

    let analysisState = 'decrypt';
    let stateExplanation = '';
    if (ncch.noCrypto) {
      analysisState = 'clean';
      stateExplanation = 'ROM is fully decrypted with NoCrypto flag active.';
    } else if (isPlain) {
      analysisState = 'patch';
      stateExplanation = 'Partitions are plaintext but NoCrypto (0x18F) is unset. Instant header forge.';
    } else {
      analysisState = 'decrypt';
      const seedNote = ncch.seedCrypto ? ' Seed crypto title (seeddb bundled).' : '';
      stateExplanation = `Encrypted NCCH (${KeyManager.cryptoMethodName(ncch.cryptoMethod)}).${seedNote}`;
    }

    return {
      status: 'valid',
      isNCSD,
      titleId: ncch.titleId,
      productCode: ncch.productCode,
      makerCode: ncch.makerCode,
      analysisState,
      stateExplanation,
      noCrypto: ncch.noCrypto,
      fixedCrypto: ncch.fixedCrypto,
      seedCrypto: ncch.seedCrypto,
      cryptoType: ncch.cryptoMethod,
      mediaUnit: ncch.mediaUnit,
      partitions,
      layout: {
        partition0Offset,
        exHeaderOffset: partition0Offset + ncch.exHeaderOffset,
        exHeaderSize: ncch.exHeaderSize,
        mediaUnit: ncch.mediaUnit
      }
    };
  }

  static async resolveSectionKey(ncch, usePrimarySlot) {
    if (ncch.fixedCrypto) {
      const key = new Uint8Array(16);
      if ((ncch.programId[4] & 0x10) !== 0x10) key.fill(0xff);
      return AESEngine.importAESCTRKey(key);
    }

    let keyY = ncch.keyY;
    if (ncch.seedCrypto) {
      const seed = GlobalKeyManager.getSeed(ncch.titleId);
      if (!seed) {
        throw new Error(
          `Seed crypto ROM (${ncch.titleId}) is missing from bundled seeddb.bin. Update Smelt or replace assets/seeddb.bin.`
        );
      }
      keyY = await KeyManager.deriveSeedKeyY(ncch.keyY, seed);
    }

    const keyX = usePrimarySlot
      ? KeyManager.SLOT0X2C_KEYX
      : KeyManager.keyXForCryptoMethod(ncch.cryptoMethod);
    return AESEngine.importAESCTRKey(KeyManager.generateNormalKey(keyX, keyY));
  }

  static async decryptSectionChunked(file, offset, length, cryptoKey, baseCounter, onBytes) {
    const CHUNK_SIZE = 8 * 1024 * 1024;
    const parts = [];
    for (let current = 0; current < length; current += CHUNK_SIZE) {
      const chunkSize = Math.min(CHUNK_SIZE, length - current);
      const chunkData = new Uint8Array(
        await file.slice(offset + current, offset + current + chunkSize).arrayBuffer()
      );
      const counter = AESEngine.incrementCounter(baseCounter, Math.floor(current / 16));
      parts.push(await AESEngine.decryptChunk(cryptoKey, counter, chunkData));
      if (onBytes) onBytes(chunkSize);
    }
    return new Blob(parts);
  }

  static async decryptExeFsSection(file, section, ncch, key2C, keySec, onBytes) {
    const split = section.splitAt || 0;
    const headerLen = Math.min(split, section.size);
    const ctr = KeyManager.generateNCCHCounter(
      ncch.partitionId,
      SECTION_EXEFS,
      ncch.version,
      section.sectionOffsetBytes,
      section.absoluteRegionOffset
    );

    const patches = [];
    if (headerLen > 0) {
      const blob = await this.decryptSectionChunked(
        file, section.offset, headerLen, key2C, ctr, onBytes
      );
      const check = new Uint8Array(await blob.slice(0, Math.min(0x200, headerLen)).arrayBuffer());
      if (headerLen >= 0x80 && !this.isValidExeFSHeader(check)) {
        throw new Error(
          `ExeFS decrypt failed for ${ncch.titleId}. Check keys/seeddb or try the macOS Smelt build.`
        );
      }
      patches.push({ offset: section.offset, size: headerLen, blob });
    }

    if (section.size > headerLen) {
      const restCtr = AESEngine.incrementCounter(ctr, Math.floor(headerLen / 16));
      const blob = await this.decryptSectionChunked(
        file,
        section.offset + headerLen,
        section.size - headerLen,
        keySec,
        restCtr,
        onBytes
      );
      patches.push({
        offset: section.offset + headerLen,
        size: section.size - headerLen,
        blob
      });
    }
    return patches;
  }

  static async collectNCCHPatches(file, ncchOffset, onBytes, log) {
    const fileSize = file.size;
    if (ncchOffset + 0x200 > fileSize) return { patches: [], patched: false, decrypted: false };

    const header = new Uint8Array(await file.slice(ncchOffset, ncchOffset + 0x200).arrayBuffer());
    const ncch = this.parseNCCHHeader(header, ncchOffset);
    if (!ncch) return { patches: [], patched: false, decrypted: false };
    if (ncch.noCrypto) return { patches: [], patched: false, decrypted: false };

    const patches = [];
    const alreadyPlain = await this.ncchSectionsLookPlain(file, ncch, ncchOffset);

    if (!alreadyPlain) {
      if (log) {
        log(
          `Decrypting NCCH @ 0x${ncchOffset.toString(16).toUpperCase()} (${KeyManager.cryptoMethodName(ncch.cryptoMethod)}${ncch.seedCrypto ? ', seed' : ''})`
        );
      }

      const key2C = await this.resolveSectionKey(ncch, true);
      const keySec =
        ncch.cryptoMethod !== 0 && !ncch.fixedCrypto
          ? await this.resolveSectionKey(ncch, false)
          : key2C;

      const sections = this.buildDecryptSections(ncch, fileSize);
      if (!sections.length && log) {
        log('No decryptable NCCH sections found (empty ExHeader/ExeFS/RomFS). Flag patch only.', 'warn');
      }

      for (const section of sections) {
        if (section.kind === 'exefs') {
          patches.push(...(await this.decryptExeFsSection(file, section, ncch, key2C, keySec, onBytes)));
          continue;
        }

        const ctr = KeyManager.generateNCCHCounter(
          ncch.partitionId,
          section.sectionType,
          ncch.version,
          section.sectionOffsetBytes,
          section.absoluteRegionOffset
        );
        const key = section.usePrimaryKey ? key2C : keySec;
        const blob = await this.decryptSectionChunked(
          file, section.offset, section.size, key, ctr, onBytes
        );

        if (section.kind === 'exheader') {
          const check = new Uint8Array(await blob.slice(0, 16).arrayBuffer());
          if (!this.isPrintableBlock(check)) {
            throw new Error(
              `AES-CTR produced garbage for ${ncch.titleId}. Seed title may be missing from bundled seeddb.bin.`
            );
          }
        }

        if (section.kind === 'romfs') {
          const check = new Uint8Array(await blob.slice(0, 4).arrayBuffer());
          if (!this.isValidRomFSMagic(check)) {
            throw new Error(
              `RomFS decrypt failed for ${ncch.titleId}. Check keys/seeddb or try the macOS Smelt build.`
            );
          }
        }

        patches.push({ offset: section.offset, size: section.size, blob });
      }
    } else if (log) {
      log(`NCCH @ 0x${ncchOffset.toString(16).toUpperCase()} is plaintext — patching NoCrypto only.`);
    }

    const patchedFlags = new Uint8Array(ncch.flags);
    patchedFlags[7] |= FLAG_NO_CRYPTO;
    patches.push({ offset: ncchOffset + 0x188, size: 8, blob: patchedFlags });
    return { patches, patched: true, decrypted: !alreadyPlain };
  }

  static coalescePatches(patches) {
    const sorted = [...patches].sort((a, b) => a.offset - b.offset);
    const out = [];

    for (const patch of sorted) {
      if (!out.length) {
        out.push({ ...patch });
        continue;
      }

      const prev = out[out.length - 1];
      const prevEnd = prev.offset + prev.size;

      if (patch.offset >= prevEnd) {
        out.push({ ...patch });
        continue;
      }

      if (patch.offset + patch.size <= prevEnd) continue;

      const trim = prevEnd - patch.offset;
      out.push({
        offset: prevEnd,
        size: patch.size - trim,
        blob: patch.blob.slice(trim)
      });
    }

    return out;
  }

  static stitchPatches(file, patches) {
    const merged = this.coalescePatches(patches);
    const blobParts = [];
    let currentOffset = 0;

    for (const patch of merged) {
      if (patch.offset > currentOffset) {
        blobParts.push(file.slice(currentOffset, patch.offset));
      }
      blobParts.push(patch.blob);
      currentOffset = patch.offset + patch.size;
    }

    if (currentOffset < file.size) {
      blobParts.push(file.slice(currentOffset, file.size));
    }

    return new Blob(blobParts, { type: 'application/octet-stream' });
  }

  static async listNCCHPartitionOffsets(file) {
    const headerBuf = await file.slice(0, 0x200).arrayBuffer();
    const view = new DataView(headerBuf);
    const magic0x100 = this.readUInt32LE(view, 0x100);
    const fileSize = file.size;
    const offsets = [];

    if (magic0x100 === NCSD_MAGIC) {
      for (let p = 0; p < 8; p++) {
        const offsetSectors = this.readUInt32LE(view, 0x120 + p * 8);
        if (!offsetSectors) continue;
        const partitionOffset = offsetSectors * 0x200;
        if (partitionOffset + 0x200 > fileSize) continue;

        const pMagic = this.readUInt32LE(
          new DataView(await file.slice(partitionOffset + 0x100, partitionOffset + 0x104).arrayBuffer()),
          0
        );
        if (pMagic === NCCH_MAGIC) offsets.push(partitionOffset);
      }
    } else if (magic0x100 === NCCH_MAGIC) {
      offsets.push(0);
    } else {
      throw new Error('Not a valid NCSD (.3ds/.cci) or NCCH container.');
    }

    return [...new Set(offsets)];
  }

  static async patchAllPartitions(file, onProgress = () => {}, log = null) {
    const offsets = await this.listNCCHPartitionOffsets(file);
    const allPatches = [];
    let patchedCount = 0;
    let decryptedAny = false;
    let bytesDone = 0;
    const hint = Math.max(file.size * 0.85, 1);
    const onBytes = (n) => {
      bytesDone += n;
      onProgress(Math.min(95, Math.floor((bytesDone / hint) * 90) + 5));
    };

    for (const offset of offsets) {
      const result = await this.collectNCCHPatches(file, offset, onBytes, log);
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
    const resultBlob = this.stitchPatches(file, allPatches);
    onProgress(100);
    return { resultBlob, patchedCount, wasClean: false, decrypted: decryptedAny };
  }
}
