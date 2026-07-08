#!/usr/bin/env python3
import os
import sys

def patch_file(filepath):
    print(f"Checking: {filepath}...")
    try:
        with open(filepath, "r+b") as f:
            # Read NCSD partition table (8 entries of 8 bytes each starting at 0x120)
            f.seek(0x120)
            partition_table = f.read(64)
            
            patched_any = False
            for p in range(8):
                offset_sectors = int.from_bytes(partition_table[p*8 : p*8 + 4], byteorder='little')
                if offset_sectors == 0:
                    continue
                    
                partition_offset = offset_sectors * 0x200
                
                # Verify NCCH magic
                f.seek(partition_offset + 0x100)
                magic = f.read(4)
                if magic != b'NCCH':
                    continue
                    
                # Read flags
                f.seek(partition_offset + 0x188)
                flags = bytearray(f.read(8))
                
                # Check if NoCrypto bit is already set (Bit 2 of flags[7], i.e., value 0x04)
                if not (flags[7] & 0x04):
                    # Set NoCrypto bit
                    flags[7] |= 0x04
                    f.seek(partition_offset + 0x188)
                    f.write(flags)
                    print(f"  -> Partition {p} header flag successfully updated to Decrypted.")
                    patched_any = True
            
            if not patched_any:
                print("  -> File is already flagged as decrypted (No Crypto). No changes needed.")
    except Exception as e:
        print(f"  -> Error processing file: {e}")

def main():
    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:
            if os.path.isfile(arg):
                patch_file(arg)
            elif os.path.isdir(arg):
                for root, dirs, files in os.walk(arg):
                    for file in files:
                        if file.lower().endswith(".3ds"):
                            patch_file(os.path.join(root, file))
            else:
                print(f"Path not found: {arg}")
    else:
        # Scan current directory
        has_files = False
        for file in os.listdir("."):
            if file.lower().endswith(".3ds"):
                has_files = True
                patch_file(file)
        if not has_files:
            print("No .3ds files found in the current directory.")
            print("Usage: python3 patch_roms.py [file1.3ds] [directory/]")

if __name__ == "__main__":
    main()
