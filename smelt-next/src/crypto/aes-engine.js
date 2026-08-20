/**
 * Smelt Next — Hardware Accelerated AES-CTR Engine via Web Crypto API
 */

export class AESEngine {
  static async importAESCTRKey(keyBytes) {
    if (typeof crypto === 'undefined' || !crypto.subtle) {
      throw new Error('Web Crypto API (crypto.subtle) is not supported in this browser environment.');
    }
    return crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-CTR' },
      false,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Decrypt with AES-CTR. Counter length is 128 so the type byte at CTR[8]
   * is not incremented (64-bit length would clobber NCCH section type).
   */
  static async decryptChunk(cryptoKey, counter, dataChunk) {
    const decryptedBuffer = await crypto.subtle.decrypt(
      {
        name: 'AES-CTR',
        counter,
        length: 128
      },
      cryptoKey,
      dataChunk
    );
    return new Uint8Array(decryptedBuffer);
  }

  /**
   * Increments a 16-byte big-endian counter by N AES blocks.
   */
  static incrementCounter(counter, blocksToAdd) {
    const updated = new Uint8Array(counter);
    if (!blocksToAdd) return updated;

    let carry = BigInt(blocksToAdd);
    for (let i = 15; i >= 0 && carry > 0n; i--) {
      const sum = BigInt(updated[i]) + (carry & 0xFFn);
      updated[i] = Number(sum & 0xFFn);
      carry = (carry >> 8n) + (sum >> 8n);
    }
    return updated;
  }
}
