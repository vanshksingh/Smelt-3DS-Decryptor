<div align="center">
  <h1>🌋 Smelt</h1>
  <p><b>A beautifully native, high-performance macOS application for decrypting and patching Nintendo 3DS ROM files.</b></p>

  [![macOS](https://img.shields.io/badge/macOS-12.0%2B-black?logo=apple&style=for-the-badge)](#)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-blue?logo=swift&style=for-the-badge)](#)
  [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](#)
</div>

  <img width="1205" height="900" alt="Screenshot 2026-07-08 at 3 17 12 AM" src="https://github.com/user-attachments/assets/04ca8a87-d5de-4313-bbf8-55262d151e55" />

---

## 📥 Download

**Looking to just use the app?**  
Download the latest compiled version of Smelt for macOS from the [**Releases Page**](https://github.com/vanshksingh/Smelt-3DS-Decryptor/releases). Just download the `.zip`, extract it, and drag `Smelt.app` into your Applications folder!

---

**Smelt** is a professional SwiftUI frontend that bundles and coordinates standard open-source command-line toolchains (`ctrtool`, `makerom`, and `ctrdecrypt`). It is designed to take the headache out of preparing 3DS ROMs for modern emulators (like Azahar, Lime3DS, or Citra) on macOS by providing a seamless, drag-and-drop batch processing experience.

Forget the terminal. Just drag your files in, and let Smelt forge them into shape.

## ✨ Key Features

- ⚡️ **Intelligent Pre-flight Analysis**: Prior to processing, the app reads NCCH headers to detect if a file is encrypted, decrypted, or simply missing the `NoCrypto` header flag (already decrypted but misreported).
- 🛠 **Fast Metadata Header Patching**: If a ROM is already decrypted but fails to boot (e.g., Error 1 in emulators), Smelt patches the `NoCrypto` flag at `0x18F` in milliseconds, avoiding lengthy and destructive full decryption passes.
- 🔓 **Full Cryptographic Decryption**: If a file is truly encrypted, Smelt wraps `cia-unix` / `ctrdecrypt` in a temporary sandbox directory to perform partition decryption and rebuild a clean `.3ds` or `.cci` container automatically.
- 🖥 **Native Mac Experience**: Built 100% in SwiftUI. Fast, beautiful, dark-mode optimized, and supports batch processing via Drag & Drop.
- 📜 **Instant Console Logs**: Built-in real-time console pane toggles instantly without UI lag, printing all CLI tool telemetry.

---

## 🚫 Why can't I output a `.cia` file?

The developer expressly declines to offer the ability to output encrypted `.cia` containers. 

The mathematical and cryptographic reality is that generating a valid `.cia` container requires Nintendo's RSA Private Keys. Unless you are planning on personally breaking into Nintendo Headquarters in Kyoto, bypassing their biometric security, and stealing their internal signing servers, any CIA you generate would be universally rejected by standard hardware and emulators for having a forged signature anyway. 

Therefore, **Smelt exclusively outputs decrypted `.cci` or `.3ds` formats**, which are universally accepted by all modern emulators. If you input a `.cia` file, Smelt will intelligently extract the contents and spit out a perfect `.cci` file for you!

---

## 🚀 Build and Deploy

To compile the native SwiftUI application and deploy it to your macOS machine:

1. Clone this repository and open your Terminal in the project directory.
2. Run the build script:
   ```bash
   bash Scripts/build_app.sh
   ```
3. The build script dynamically resolves the workspace root, compiles the binary, copies the toolchain resources, cleans Gatekeeper quarantine flags (`com.apple.quarantine`), and deploys `Smelt.app` directly to your `~/Downloads/Smelt.app` folder!

---

## ⚖️ Legal & EULA

This Software is designed **solely for the purpose of personal data archival, format shifting, and interoperability of legally obtained, physically owned game media.**

- **NO PIRACY**: You explicitly represent and warrant that any and all files processed through this Software have been legally dumped directly from hardware or media that you legally purchased and own.
- **NO KEYS PROVIDED**: This software does **not** contain Nintendo's proprietary cryptographic AES or RSA keys. 
- **DISCLAIMER**: The developer strictly condemns software piracy. The developer shall not be held responsible for your actions should you choose to violate international copyright laws.

Upon launch, the application displays a comprehensive End-User License Agreement (EULA). You must agree to these terms to use the software.

---

## 🙏 Acknowledgements & Credits

Smelt is built on top of foundational utilities created by the legendary 3DS homebrew and preservation communities. We owe everything to the following contributors:

* **[profi200](https://github.com/profi200)**: Original developer of `makerom` and `ctrtool`, essential core components of the [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR) toolchain.
* **[3DSGuy](https://github.com/3DSGuy)**: Primary maintainer of the modernized [Project_CTR](https://github.com/3DSGuy/Project_CTR) suite.
* **[matiffeder](https://github.com/matiffeder)**: Creator of the original [Batch CIA 3DS Decryptor](https://github.com/matiffeder/stuff) scripts upon which this workflow was modeled.
* **54634564**: Developer of the core `decrypt` utility.
* **[shijimasoft](https://github.com/shijimasoft)**: Creator of [ctrdecrypt](https://github.com/shijimasoft/ctrdecrypt), the NCCH decryption engine.
