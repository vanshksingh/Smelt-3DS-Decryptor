/**
 * Smelt Next — 3DS Cryptographic Key & Seed Database Manager
 */

export class KeyManager {
  constructor() {
    this.seeds = new Map(); // TitleID hex -> 16-byte Uint8Array seed
    this.customKeys = new Map(); // Slot -> 16-byte key
    this.isSeedDbLoaded = false;
  }

  /**
   * Parses standard seeddb.bin binary format
   * @param {ArrayBuffer|Uint8Array} buffer 
   */
  loadSeedDB(buffer) {
    const data = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

    if (data.length < 4) return 0;
    const count = view.getUint32(0, true);
    let loaded = 0;

    for (let i = 0; i < count; i++) {
      const offset = 16 + i * 32;
      if (offset + 32 > data.length) break;

      const titleIdBytes = data.slice(offset, offset + 8);
      const titleIdHex = Array.from(titleIdBytes)
        .reverse()
        .map(b => b.toString(16).padStart(2, '0').toUpperCase())
        .join('');

      const seedBytes = data.slice(offset + 8, offset + 24);
      this.seeds.set(titleIdHex, seedBytes);
      loaded++;
    }

    this.isSeedDbLoaded = true;
    return loaded;
  }

  /**
   * Retrieves seed for TitleID if available
   */
  getSeed(titleIdHex) {
    const cleanId = titleIdHex.toUpperCase();
    return this.seeds.get(cleanId) || null;
  }

  /**
   * Generates AES Initial Counter (IV/Counter) for NCCH partition
   * In 3DS CTR mode, counter = [Title ID (8 bytes reversed), Section Type (1 byte), 0x00...0x00, Block Offset >> 4]
   */
  static generateNCCHCounter(titleIdBytes, sectionType, blockOffsetBytes = 0) {
    const iv = new Uint8Array(16);
    
    // Copy Title ID (reversed / big-endian in counter block)
    for (let i = 0; i < 8; i++) {
      iv[i] = titleIdBytes[7 - i];
    }
    
    iv[8] = sectionType & 0xFF; // 1 = ExHeader, 2 = ExeFS, 3 = RomFS, etc.
    
    // Set 64-bit Big Endian counter at iv[8..15] or iv[12..15] offset
    const blockIndex = Math.floor(blockOffsetBytes / 16);
    iv[12] = (blockIndex >>> 24) & 0xFF;
    iv[13] = (blockIndex >>> 16) & 0xFF;
    iv[14] = (blockIndex >>> 8) & 0xFF;
    iv[15] = blockIndex & 0xFF;

    return iv;
  }
}

export const GlobalKeyManager = new KeyManager();
