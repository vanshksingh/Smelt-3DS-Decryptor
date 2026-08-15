<div align="center">
  <h1>Smelt</h1>
  <p><b>A native, high-performance macOS application for decrypting and patching Nintendo 3DS ROM files.</b></p>

  [![macOS](https://img.shields.io/badge/macOS-12.0%2B-black?logo=apple&style=for-the-badge)](#)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-blue?logo=swift&style=for-the-badge)](#)
  [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](#)
</div>

<img width="1205" height="900" alt="Screenshot 2026-07-08 at 3 17 12 AM" src="https://github.com/user-attachments/assets/04ca8a87-d5de-4313-bbf8-55262d151e55" />

---

## Download & Installation

Looking to use the app?  
Download the latest compiled version of Smelt for macOS from the [**Releases Page**](https://github.com/vanshksingh/Smelt-3DS-Decryptor/releases). Extract the `.zip` archive and move `Smelt.app` into your `/Applications` folder.

### macOS Gatekeeper Notice
Because Smelt is self-signed without an Apple Developer account, macOS Gatekeeper may show an "unidentified developer" warning or report that the application is damaged.

To open the app, do one of the following:
- **Right-click (or Control-click)** `Smelt.app` in your Applications folder and select **Open**, then confirm with **Open**, OR
- Open Terminal and run the following command to remove the quarantine flag:
  ```bash
  xattr -cr /Applications/Smelt.app
  ```

---

**Smelt** is a SwiftUI frontend that bundles and coordinates standard open-source command-line toolchains (`ctrtool`, `makerom`, and `ctrdecrypt`). It is designed to simplify preparing 3DS ROMs for modern emulators (such as Azahar, Lime3DS, or Citra) on macOS by providing a seamless, drag-and-drop batch processing experience.

## Key Features

- **Intelligent Pre-flight Analysis**: Reads NCCH headers prior to processing to detect whether a file is encrypted, decrypted, or simply missing the `NoCrypto` header flag.
- **Fast Metadata Header Patching**: If a ROM is already decrypted but fails to boot (e.g., Error 1 in emulators), Smelt patches the `NoCrypto` flag at `0x18F` in milliseconds, avoiding lengthy full decryption passes.
- **Full Cryptographic Decryption**: If a file is encrypted, Smelt coordinates `cia-unix` / `ctrdecrypt` in a temporary sandbox directory to perform partition decryption and rebuild a clean `.3ds` or `.cci` container automatically.
- **Native Mac Experience**: Built with 100% native SwiftUI. Optimized for dark mode, fast performance, and drag-and-drop batch processing.
- **Real-Time Console Logs**: Built-in console pane toggles instantly without UI lag, displaying live CLI telemetry.

---

## Why can't I output a `.cia` file?

Smelt does not offer an option to output encrypted `.cia` containers.

Generating a valid `.cia` container requires Nintendo RSA private keys. Any custom-generated CIA without valid signatures would be rejected by standard hardware and emulators.

Therefore, **Smelt outputs decrypted `.cci` or `.3ds` formats**, which are standard across all modern emulators. If you input a `.cia` file, Smelt extracts the contents and converts them into a decrypted `.cci` file.

---

## Build and Deploy

To compile the native SwiftUI application locally:

1. Clone this repository and open Terminal in the project directory.
2. Run the build script:
   ```bash
   bash Scripts/build_app.sh
   ```
3. The build script resolves the workspace, compiles the Swift binary, bundles the required toolchain resources, performs deep ad-hoc code signing, and deploys `Smelt.app` directly to `~/Downloads/Smelt.app`.

---

## Legal & EULA

This software is designed solely for personal data archival, format shifting, and interoperability of legally obtained, physically owned game media.

- **No Piracy**: Any and all files processed through this software must be legally dumped directly from hardware or media that you own.
- **No Keys Provided**: This software does not distribute Nintendo proprietary cryptographic AES or RSA keys.
- **Disclaimer**: The developer does not support software piracy and shall not be held responsible for misuse of this tool.

---

## Acknowledgements & Credits

Smelt builds upon utilities created by the 3DS homebrew and preservation community:

- **[profi200](https://github.com/profi200)**: Developer of `makerom` and `ctrtool`, core components of the [3DSGuy/Project_CTR](https://github.com/3DSGuy/Project_CTR) toolchain.
- **[3DSGuy](https://github.com/3DSGuy)**: Maintainer of the modernized [Project_CTR](https://github.com/3DSGuy/Project_CTR) suite.
- **[matiffeder](https://github.com/matiffeder)**: Creator of the original [Batch CIA 3DS Decryptor](https://github.com/matiffeder/stuff) workflow.
- **54634564**: Developer of the core `decrypt` utility.
- **[shijimasoft](https://github.com/shijimasoft)**: Creator of [ctrdecrypt](https://github.com/shijimasoft/ctrdecrypt), the NCCH decryption engine.
