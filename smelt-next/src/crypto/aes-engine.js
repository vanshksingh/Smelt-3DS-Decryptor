/**
 * Smelt Next — Hardware Accelerated AES-CTR Engine via Web Crypto API
 */

export class AESEngine {
  /**
   * Imports a raw 128-bit key into Web Crypto SubtleCrypto
   * @param {Uint8Array} keyBytes 16-byte key
   * @returns {Promise<CryptoKey>}
   */
  static async importAESCTRKey(keyBytes) {
    if (typeof crypto === 'undefined' || !crypto.subtle) {
      throw new Error('Web Crypto API (crypto.subtle) is not supported in this browser environment.');
    }
    return await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-CTR' },
      false,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Decrypts a chunk of data using Web Crypto AES-CTR
   * @param {CryptoKey} cryptoKey 
   * @param {Uint8Array} counter 16-byte IV/Counter
   * @param {Uint8Array} dataChunk Ciphertext bytes
   * @returns {Promise<Uint8Array>} Plaintext bytes
   */
  static async decryptChunk(cryptoKey, counter, dataChunk) {
    const decryptedBuffer = await crypto.subtle.decrypt(
      {
        name: 'AES-CTR',
        counter: counter,
        length: 64 // 64-bit counter length
      },
      cryptoKey,
      dataChunk
    );
    return new Uint8Array(decryptedBuffer);
  }

  /**
   * Increments a 16-byte Big-Endian counter by a specified number of blocks (16 bytes each)
   * @param {Uint8Array} counter 
   * @param {number} blocksToAdd 
   */
  static incrementCounter(counter, blocksToAdd) {
    const updated = new Uint8Array(counter);
    let carry = blocksToAdd;
    for (let i = 15; i >= 0 && carry > 0; i--) {
      const sum = updated[i] + (carry & 0xFF);
      updated[i] = sum & 0xFF;
      carry = (carry >>> 8) + (sum >>> 8);
    }
    return updated;
  }
}
