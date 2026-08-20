/**
 * Smelt Next — 3DS key scrambler, NCCH counters, seeddb
 */

export class KeyManager {
  constructor() {
    this.seeds = new Map();
    this.isSeedDbLoaded = false;
  }

  loadSeedDB(buffer) {
    const data = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    if (data.length < 4) return 0;

    const count = view.getUint32(0, true);
    let loaded = 0;
    for (let i = 0; i < count; i++) {
      const offset = 16 + i * 32;
      if (offset + 32 > data.length) break;
      const titleIdHex = Array.from(data.slice(offset, offset + 8))
        .reverse()
        .map((b) => b.toString(16).padStart(2, '0').toUpperCase())
        .join('');
      this.seeds.set(titleIdHex, data.slice(offset + 8, offset + 24));
      loaded++;
    }
    this.isSeedDbLoaded = true;
    return loaded;
  }

  getSeed(titleIdHex) {
    return this.seeds.get(String(titleIdHex || '').toUpperCase()) || null;
  }

  /**
   * NCCH AES-CTR IV.
   * v0/v2 (CFA/CXI): reversed partition ID + section type + block index in [12..15]
   * v1 (prototype): partition ID + absolute region byte offset in [12..15]
   */
  static generateNCCHCounter(
    partitionIdBytes,
    sectionType,
    ncchVersion = 0,
    sectionOffsetBytes = 0,
    absoluteRegionOffset = 0
  ) {
    const iv = new Uint8Array(16);
    if (ncchVersion === 1) {
      for (let i = 0; i < 8; i++) iv[i] = partitionIdBytes[i];
      const x = absoluteRegionOffset + sectionOffsetBytes;
      iv[12] = (x >>> 24) & 0xff;
      iv[13] = (x >>> 16) & 0xff;
      iv[14] = (x >>> 8) & 0xff;
      iv[15] = x & 0xff;
    } else {
      for (let i = 0; i < 8; i++) iv[i] = partitionIdBytes[7 - i];
      iv[8] = sectionType & 0xff;
      const blockIndex = Math.floor(sectionOffsetBytes / 16);
      iv[12] = (blockIndex >>> 24) & 0xff;
      iv[13] = (blockIndex >>> 16) & 0xff;
      iv[14] = (blockIndex >>> 8) & 0xff;
      iv[15] = blockIndex & 0xff;
    }
    return iv;
  }

  static SLOT0X2C_KEYX = new Uint8Array([
    0xb9, 0x8e, 0x95, 0xce, 0xca, 0x3e, 0x4d, 0x17,
    0x1f, 0x76, 0xa9, 0x4d, 0xe9, 0x34, 0xc0, 0x53
  ]);

  static SLOT0X25_KEYX = new Uint8Array([
    0xce, 0xe9, 0xd9, 0xc8, 0x6c, 0xb9, 0x6b, 0x0b,
    0x5a, 0x7a, 0x3e, 0x76, 0x8b, 0xc7, 0xfa, 0x91
  ]);

  static SLOT0X18_KEYX = new Uint8Array([
    0x82, 0xe9, 0xca, 0xfa, 0xce, 0xe9, 0xcb, 0x98,
    0x3c, 0xe6, 0x39, 0x50, 0x72, 0x9c, 0x46, 0x41
  ]);

  static SLOT0X1B_KEYX = new Uint8Array([
    0x45, 0xad, 0x04, 0x95, 0x39, 0x42, 0x98, 0x1b,
    0xb4, 0x66, 0x6e, 0x90, 0x08, 0x0a, 0x57, 0xf9
  ]);

  static SCRAMBLER_CONST = 0x1FF9E9AAC5FE0408024591DC5D52768An;

  static rotl128(value, shift) {
    const mask128 = (1n << 128n) - 1n;
    return ((value << BigInt(shift)) & mask128) | (value >> BigInt(128 - shift));
  }

  static uint8ArrayToBigInt(arr) {
    let result = 0n;
    for (let i = 0; i < arr.length; i++) {
      result = (result << 8n) | BigInt(arr[i]);
    }
    return result;
  }

  static bigIntToUint8Array(num, size) {
    const arr = new Uint8Array(size);
    for (let i = size - 1; i >= 0; i--) {
      arr[i] = Number(num & 0xffn);
      num >>= 8n;
    }
    return arr;
  }

  static generateNormalKey(keyX, keyY) {
    const x = this.uint8ArrayToBigInt(keyX);
    const y = this.uint8ArrayToBigInt(keyY);
    const added = (this.rotl128(x, 2) ^ y) + this.SCRAMBLER_CONST;
    const normalKey = this.rotl128(added & ((1n << 128n) - 1n), 87);
    return this.bigIntToUint8Array(normalKey, 16);
  }

  static keyXForCryptoMethod(method) {
    switch (method) {
      case 0x01: return this.SLOT0X25_KEYX;
      case 0x0a: return this.SLOT0X18_KEYX;
      case 0x0b: return this.SLOT0X1B_KEYX;
      default: return this.SLOT0X2C_KEYX;
    }
  }

  static cryptoMethodName(method) {
    switch (method) {
      case 0x01: return 'Secure2 (0x25)';
      case 0x0a: return 'Secure3 (0x18)';
      case 0x0b: return 'Secure4 (0x1B)';
      default: return 'Standard (0x2C)';
    }
  }

  static async deriveSeedKeyY(baseKeyY, seedBytes) {
    const joined = new Uint8Array(32);
    joined.set(baseKeyY, 0);
    joined.set(seedBytes, 16);
    const digest = await crypto.subtle.digest('SHA-256', joined);
    return new Uint8Array(digest).slice(0, 16);
  }
}

export const GlobalKeyManager = new KeyManager();
