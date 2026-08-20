/**
 * Smelt Next — NCCH & NCSD (3DS/CCI) Container Parser and Header Engine
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
   * Analyzes an input 3DS / CCI file buffer or slice (at least first 2MB)
   * @param {Uint8Array|ArrayBuffer} headerData First 1-2MB of file
   * @param {number} fileSize Total size of file in bytes
   */
  static analyzeContainer(headerData, fileSize) {
    const data = headerData instanceof Uint8Array ? headerData : new Uint8Array(headerData);
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

    if (fileSize < 0x2000) {
      return { status: 'invalid', message: 'File is too small to be a valid 3DS container.' };
    }

    // Check if directly NCCH or NCSD container
    let isNCSD = false;
    if (data.length >= 0x104) {
      const magic0x100 = this.readUInt32LE(view, 0x100);
      if (magic0x100 === NCSD_MAGIC) {
        isNCSD = true;
      }
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
    }

    // Verify Partition 0 NCCH Header at partition0Offset + 0x100
    const ncchHeaderOffset = partition0Offset + 0x100;
    if (data.length < ncchHeaderOffset + 0x100) {
      return {
        status: 'invalid',
        message: 'Could not read primary NCCH header within buffer slice.'
      };
    }

    const ncchMagic = this.readUInt32LE(view, ncchHeaderOffset);
    if (ncchMagic !== NCCH_MAGIC) {
      return {
        status: 'invalid',
        message: 'Missing valid NCCH signature in primary partition.'
      };
    }

    // Extract NCCH Header Info
    // Title ID: 0x18..0x20 (8 bytes)
    const titleIdBytes = data.slice(ncchHeaderOffset + 0x18, ncchHeaderOffset + 0x20);
    const titleId = this.bytesToHex(titleIdBytes, true);

    // Product Code: 0x50..0x60 (16 bytes ASCII)
    const productCodeBytes = data.slice(ncchHeaderOffset + 0x50, ncchHeaderOffset + 0x60);
    const productCode = this.bytesToAscii(productCodeBytes) || 'N/A';

    // Maker Code: 0x10..0x12 (2 bytes ASCII)
    const makerCodeBytes = data.slice(ncchHeaderOffset + 0x10, ncchHeaderOffset + 0x12);
    const makerCode = this.bytesToAscii(makerCodeBytes) || '00';

    // Flags: 0x188..0x190 (8 bytes)
    const flagsOffset = ncchHeaderOffset + 0x88; // 0x100 + 0x88 = 0x188
    const flags = data.slice(flagsOffset, flagsOffset + 8);
    const cryptoType = flags[3];
    const unitShift = Math.min(flags[6], 16);
    const mediaUnit = 512 * (1 << unitShift);
    const noCrypto = (flags[7] & 0x04) !== 0;
    const fixedCrypto = (flags[7] & 0x01) !== 0;

    // Content offsets in media units
    const exHeaderUnits = this.readUInt32LE(view, ncchHeaderOffset + 0xA0);
    const exHeaderByteOffset = partition0Offset + (exHeaderUnits * mediaUnit);

    const plainOffsetUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x60);
    const plainSizeUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x64);
    const logoOffsetUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x68);
    const logoSizeUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x6C);
    const exefsOffsetUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x70);
    const exefsSizeUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x74);
    const romfsOffsetUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x80);
    const romfsSizeUnits = this.readUInt32LE(view, ncchHeaderOffset + 0x84);

    // Check ExeFS / ExHeader plaintext status
    let isExHeaderPrintable = false;
    if (data.length >= exHeaderByteOffset + 8 && exHeaderUnits > 0) {
      const testExHeader = data.slice(exHeaderByteOffset, exHeaderByteOffset + 8);
      isExHeaderPrintable = Array.from(testExHeader).every(
        b => (b >= 0x20 && b < 0x7F) || b === 0
      );
    }

    // Determine state
    let analysisState = 'decrypt';
    let stateExplanation = '';

    if (noCrypto) {
      analysisState = 'clean';
      stateExplanation = 'ROM is fully decrypted and has the NoCrypto flag enabled.';
    } else if (isExHeaderPrintable) {
      // ExeFS is already unencrypted plaintext, but NoCrypto flag is missing!
      analysisState = 'patch';
      stateExplanation = 'Decrypted content detected with missing NoCrypto flag (Causes Emulator Error 1). Needs instant 1ms header patch.';
    } else {
      analysisState = 'decrypt';
      stateExplanation = 'Encrypted NCCH partitions detected. Requires AES-CTR partition decryption.';
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
        ncchHeaderOffset,
        flagsOffset,
        exHeaderOffset: exHeaderByteOffset,
        plainOffset: partition0Offset + plainOffsetUnits * mediaUnit,
        plainSize: plainSizeUnits * mediaUnit,
        logoOffset: partition0Offset + logoOffsetUnits * mediaUnit,
        logoSize: logoSizeUnits * mediaUnit,
        exefsOffset: partition0Offset + exefsOffsetUnits * mediaUnit,
        exefsSize: exefsSizeUnits * mediaUnit,
        romfsOffset: partition0Offset + romfsOffsetUnits * mediaUnit,
        romfsSize: romfsSizeUnits * mediaUnit
      }
    };
  }

  /**
   * Patches the NoCrypto flag (flags[7] |= 0x04) directly into an NCSD/NCCH header buffer
   * @param {Uint8Array} buffer Must contain at least the header region
   * @returns {boolean} True if flags were modified
   */
  static patchNoCryptoFlag(buffer) {
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    let patchedAny = false;

    // Check if NCSD
    if (buffer.length >= 0x160) {
      const ncsdMagic = this.readUInt32LE(view, 0x100);
      if (ncsdMagic === NCSD_MAGIC) {
        for (let p = 0; p < 8; p++) {
          const offsetSectors = this.readUInt32LE(view, 0x120 + p * 8);
          if (offsetSectors === 0) continue;
          const partitionOffset = offsetSectors * 0x200;
          if (buffer.length >= partitionOffset + 0x190) {
            const magic = this.readUInt32LE(view, partitionOffset + 0x100);
            if (magic === NCCH_MAGIC) {
              const flagPos = partitionOffset + 0x18F; // 0x188 + 7
              if ((buffer[flagPos] & 0x04) === 0) {
                buffer[flagPos] |= 0x04;
                patchedAny = true;
              }
            }
          }
        }
        return patchedAny;
      }
    }

    // Check if direct NCCH
    if (buffer.length >= 0x190) {
      const magic = this.readUInt32LE(view, 0x100);
      if (magic === NCCH_MAGIC) {
        const flagPos = 0x18F;
        if ((buffer[flagPos] & 0x04) === 0) {
          buffer[flagPos] |= 0x04;
          return true;
        }
      }
    }

    return patchedAny;
  }
}
