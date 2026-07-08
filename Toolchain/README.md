# 3DS ROM Decryption & Patching Toolkit

This toolkit contains helper tools to decrypt and fix Nintendo 3DS ROM files (`.3ds` or `.cia`) so they can run on emulators like Citra/Azahar on macOS.

---

## Included Files

1. **`cia-unix`**: The main community-made Unix batch decryptor wrapper.
2. **`ctrdecrypt`**: The core command-line utility used to decrypt NCCH partitions.
3. **`ctrtool`**: A utility to inspect 3DS ROM/CIA headers and verify if they are decrypted.
4. **`makerom`**: A tool to rebuild CTR/3DS executable packages.
5. **`seeddb.bin`**: Cryptographic seed database used by `ctrtool` and `makerom` for newer games.
6. **`dltools.sh`**: A shell script to download the original binaries if they are ever missing or updated.
7. **`patch_roms.py`**: A helper Python 3 script to fix header flags for ROMs that are already decrypted but incorrectly marked as "Encrypted" (which causes emulators to crash).

---

## Prerequisites (macOS Setup)

Before running the tools, you must grant executable permissions and clear any macOS security blocks (since they are downloaded from GitHub):

```bash
# 1. Open Terminal and navigate to this folder
cd /path/to/this/folder

# 2. Grant executable permissions to all binaries and scripts
chmod +x cia-unix ctrdecrypt ctrtool makerom dltools.sh patch_roms.py

# 3. Clear the macOS quarantine attribute so macOS doesn't block them from running
xattr -d -r com.apple.quarantine * 2>/dev/null
```

---

## How to Use

### Scenario A: The ROM is Encrypted
If you have a fresh, encrypted game dump (`.3ds` or `.cia`):

1. Put your `.3ds` or `.cia` file in the same directory as these tools.
2. Run the decryptor:
   ```bash
   ./cia-unix
   ```
3. The tool will decrypt the file and output `<game>-decrypted.3ds`.

---

### Scenario B: The ROM is Already Decrypted, But Fails to Boot (Error 1 / "Unknown Error")
Many 3DS ROMs downloaded online are already decrypted but have incorrect header flags, making the emulator think they are encrypted. 

If your emulator throws **"An unknown error occurred (Error 1)"**, use the Python patcher script:

1. Run the script on the specific file:
   ```bash
   python3 patch_roms.py "/path/to/your/game.3ds"
   ```
   *Or scan and fix all `.3ds` files in the current folder:*
   ```bash
   python3 patch_roms.py
   ```
2. The script will patch the **NoCrypto** flag in the header. The file will now load perfectly in the emulator.
