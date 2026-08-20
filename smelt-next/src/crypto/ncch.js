/**
 * Smelt Next — NCCH & NCSD (3DS/CCI) Container Parser and Direct-Stream Patching Engine
 */

export const NCCH_MAGIC = 0x4843434e; // 'NCCH' in little endian (0x4E, 0x43, 0x43, 0x48)
export const NCSD_MAGIC = 0x4453434e; // 'NCSD' in little endian (0x4E, 0x43, 0x53, 0x44)

export class NCCHReader {
  /**
   * Reads 32-bit unsigned integer in Little Endian from DataView or Uint8Array
   */
  static readUInt32LE(buffer, offset = 0) {
    if (buffer instanceof DataView) {
      return buffer.getUint32(offset, true);
    }
    return (
      (buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24)) >>> 0
    );
  }

  /**
   * Reads 64-bit unsigned integer in Little Endian
   */
  static readUInt64LE(buffer, offset = 0) {
    if (buffer instanceof DataView) {
      return buffer.getBigUint64(offset, true);
    }
    const low = BigInt(this.readUInt32LE(buffer, offset));
    const high = BigInt(this.readUInt32LE(buffer, offset + 4));
    return (high << 32n) | low;
  }

  /**
   * Converts byte array to hex string
   */
  static bytesToHex(bytes, reverse = false) {
    const arr = reverse ? Array.from(bytes).reverse() : Array.from(bytes);
    return arr.map(b => b.toString(16).padStart(2, '0').toUpperCase()).join('');
  }

  /**
   * Parses ASCII string from byte array
   */
  static bytesToAscii(bytes) {
    let str = '';
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 0) break;
      if (bytes[i] >= 32 && bytes[i] <= 126) {
        str += String.fromCharCode(bytes[i]);
      }
    }
    return str.trim();
  }

  /**
   * Analyzes an input 3DS / CCI / CXI file. Reads specific header regions directly from the File object.
   * @param {File|Blob} file The input file
   */
  static async analyzeFile(file) {
    const fileSize = file.size;
    if (fileSize < 0x2000) {
      return { status: 'invalid', message: 'File is too small to be a valid 3DS container.' };
    }

    // 1. Read first 0x200 bytes (NCSD header / Partition Table)
    const headerBuf = await file.slice(0, 0x200).arrayBuffer();
    const headerData = new Uint8Array(headerBuf);
    const view = new DataView(headerBuf);

    let isNCSD = false;
    const magic0x100 = this.readUInt32LE(view, 0x100);
    if (magic0x100 === NCSD_MAGIC) {
      isNCSD = true;
    }

    let partitions = [];
    let partition0Offset = 0;

    if (isNCSD) {
      // NCSD Partition Table is at 0x120 (8 entries of 8 bytes: 4 bytes sector offset, 4 bytes sector length)
      for (let p = 0; p < 8; p++) {
        const pOffset = 0x120 + p * 8;
        const offsetSectors = this.readUInt32LE(view, pOffset);
        const lengthSectors = this.readUInt32LE(view, pOffset + 4);
        if (offsetSectors > 0 && lengthSectors > 0) {
          const byteOffset = offsetSectors * 0x200;
          const byteLength = lengthSectors * 0x200;
          partitions.push({
            index: p,
            offsetSectors,
            lengthSectors,
            byteOffset,
            byteLength
          });
        }
      }
      if (partitions.length > 0) {
        partition0Offset = partitions[0].byteOffset;
      }
    } else {
      // Direct NCCH file
      partitions.push({
        index: 0,
        offsetSectors: 0,
        lengthSectors: Math.floor(fileSize / 512),
        byteOffset: 0,
        byteLength: fileSize
      });
      partition0Offset = 0;
    }

    // 2. Read Partition 0 NCCH Header (0x200 bytes starting at partition0Offset)
    const p0HeaderSlice = await file.slice(partition0Offset, partition0Offset + 0x200).arrayBuffer();
    const p0Data = new Uint8Array(p0HeaderSlice);
    const p0View = new DataView(p0HeaderSlice);

    if (p0Data.length < 0x200) {
      return { status: 'invalid', message: 'Could not read partition 0 NCCH header.' };
    }

    const ncchMagic = this.readUInt32LE(p0View, 0x100);
    if (ncchMagic !== NCCH_MAGIC) {
      return { status: 'invalid', message: 'Missing valid NCCH signature in primary partition.' };
    }

    // Extract Title ID (0x18..0x20)
    const titleIdBytes = p0Data.slice(0x118, 0x120);
    const titleId = this.bytesToHex(titleIdBytes, true);

    // Product Code (0x50..0x60)
    const productCodeBytes = p0Data.slice(0x150, 0x160);
    const productCode = this.bytesToAscii(productCodeBytes) || 'CTR-N-3DS';

    // Maker Code (0x10..0x12)
    const makerCodeBytes = p0Data.slice(0x110, 0x112);
    const makerCode = this.bytesToAscii(makerCodeBytes) || '00';

    // Flags (0x188..0x190)
    const flags = p0Data.slice(0x188, 0x190);
    const cryptoType = flags[3];
    const unitShift = Math.min(flags[6], 16);
    const mediaUnit = 512 * (1 << unitShift);
    const noCrypto = (flags[7] & 0x04) !== 0;
    const fixedCrypto = (flags[7] & 0x01) !== 0;

    // ExHeader offset
    const exHeaderUnits = this.readUInt32LE(p0View, 0x1A0);
    const exHeaderByteOffset = partition0Offset + (exHeaderUnits * mediaUnit);

    // 3. Read ExHeader first 8 bytes to verify plaintext status
    let isExHeaderPrintable = false;
    if (exHeaderUnits > 0 && exHeaderByteOffset + 8 <= fileSize) {
      const exHeaderSlice = await file.slice(exHeaderByteOffset, exHeaderByteOffset + 8).arrayBuffer();
      const exHeaderData = new Uint8Array(exHeaderSlice);
      if (exHeaderData.length >= 8) {
        isExHeaderPrintable = Array.from(exHeaderData).every(
          b => (b >= 0x20 && b < 0x7F) || b === 0
        );
      }
    }

    // Determine state
    let analysisState = 'decrypt';
    let stateExplanation = '';

    if (noCrypto) {
      analysisState = 'clean';
      stateExplanation = 'ROM is fully decrypted with NoCrypto flag active.';
    } else if (isExHeaderPrintable || exHeaderUnits === 0) {
      // Content is decrypted plaintext, but NoCrypto flag is missing
      analysisState = 'patch';
      stateExplanation = 'Decrypted partitions detected missing NoCrypto flag (0x18F). Instant header forge ready.';
    } else {
      analysisState = 'decrypt';
      stateExplanation = 'Encrypted NCCH partitions detected. Ready for Forge patch.';
    }

    return {
      status: 'valid',
      isNCSD,
      titleId,
      productCode,
      makerCode,
      analysisState,
      stateExplanation,
      noCrypto,
      fixedCrypto,
      cryptoType,
      mediaUnit,
      partitions,
      layout: {
        partition0Offset,
        exHeaderOffset: exHeaderByteOffset,
        exHeaderUnits,
        mediaUnit
      }
    };
  }

  /**
   * Patches ALL partitions in an NCSD / NCCH / CIA container with the NoCrypto flag.
   * Uses precise sub-slice replacement: zero memory overhead, instant processing even for 4GB files.
   * @param {File|Blob} file 
   * @param {Function} onProgress 
   * @returns {Promise<{ resultBlob: Blob, patchedCount: number, wasClean: boolean }>}
   */
  static async patchAllPartitions(file, onProgress = () => {}) {
    const fileSize = file.size;
    const patches = []; // Array of { offset: number, bytes: Uint8Array }

    // 1. Check if NCSD container
    const headerBuf = await file.slice(0, 0x200).arrayBuffer();
    const headerData = new Uint8Array(headerBuf);
    const view = new DataView(headerBuf);
    const magic0x100 = this.readUInt32LE(view, 0x100);

    let wasClean = true;
    let patchedCount = 0;

    if (magic0x100 === NCSD_MAGIC) {
      // NCSD: Scan all 8 partitions from table at 0x120
      for (let p = 0; p < 8; p++) {
        const pOffset = 0x120 + p * 8;
        const offsetSectors = this.readUInt32LE(view, pOffset);
        if (offsetSectors === 0) continue;

        const partitionOffset = offsetSectors * 0x200;
        if (partitionOffset + 0x200 > fileSize) continue;

        // Read partition header (0x200 bytes)
        const pBuf = await file.slice(partitionOffset, partitionOffset + 0x200).arrayBuffer();
        const pData = new Uint8Array(pBuf);
        const pView = new DataView(pBuf);

        // Check NCCH magic at partitionOffset + 0x100
        if (this.readUInt32LE(pView, 0x100) === NCCH_MAGIC) {
          const flagPos = 0x188;
          const currentFlags = pData.slice(flagPos, flagPos + 8);
          
          if ((currentFlags[7] & 0x04) === 0) {
            wasClean = false;
            const patchedFlags = new Uint8Array(currentFlags);
            patchedFlags[7] |= 0x04; // Set NoCrypto bit

            patches.push({
              offset: partitionOffset + flagPos,
              bytes: patchedFlags
            });
            patchedCount++;
          }
        }
      }
    } else if (magic0x100 === NCCH_MAGIC) {
      // Direct NCCH file (partition at offset 0)
      const currentFlags = headerData.slice(0x188, 0x190);
      if ((currentFlags[7] & 0x04) === 0) {
        wasClean = false;
        const patchedFlags = new Uint8Array(currentFlags);
        patchedFlags[7] |= 0x04;

        patches.push({
          offset: 0x188,
          bytes: patchedFlags
        });
        patchedCount++;
      }
    }

    onProgress(50);

    // If already clean and no patches required, return original file
    if (patches.length === 0) {
      onProgress(100);
      return { resultBlob: file, patchedCount: 0, wasClean: true };
    }

    // Sort patches by file offset ascending
    patches.sort((a, b) => a.offset - b.offset);

    // Assemble final Blob by stitching untouched file slices and patched flag bytes
    const blobParts = [];
    let currentOffset = 0;

    for (const patch of patches) {
      if (patch.offset > currentOffset) {
        blobParts.push(file.slice(currentOffset, patch.offset));
      }
      blobParts.push(patch.bytes);
      currentOffset = patch.offset + patch.bytes.length;
    }

    if (currentOffset < fileSize) {
      blobParts.push(file.slice(currentOffset, fileSize));
    }

    onProgress(100);
    const resultBlob = new Blob(blobParts, { type: 'application/octet-stream' });
    return { resultBlob, patchedCount, wasClean: false };
  }
}
