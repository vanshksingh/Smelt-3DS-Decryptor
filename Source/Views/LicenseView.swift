import SwiftUI
import AppKit

struct LicenseGate: View {
    var onAgree: () -> Void
    @Environment(\.palette) private var palette
    @State private var hasAcceptedCheckbox = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            LicenseView(checkbox: $hasAcceptedCheckbox, onAgree: onAgree)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LicenseView: View {
    @Binding var checkbox: Bool
    var onAgree: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20))
                    .foregroundColor(Palette.blue)
                Text("END-USER LICENSE AGREEMENT AND TERMS OF SERVICE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    bodyText("IMPORTANT - READ CAREFULLY: This End-User License Agreement (\"EULA\") is a legal agreement between you (either an individual or a single entity) and the developer of the Smelt software utility (\"Software\"). By clicking \"Agree\" and using the Software, you agree to be bound by the terms of this EULA. If you do not agree to the terms of this EULA, do not use the Software and click \"Disagree & Exit\".")

                    section("0. DECLARATION OF REALITY AND INTENT", "By using Smelt, you acknowledge that this Software is simply a graphical user interface (frontend) that coordinates external, third-party CLI tools (ctrtool, makerom, and ctrdecrypt) to assist with file decryption. You agree that if your Mac runs hot enough to fry eggs, sounds like a commercial airplane preparing for takeoff, or if you run out of drive space because you attempted to decrypt massive file dumps all at once, that is entirely your issue. You certify that you are using this utility exclusively for personal backups of games you legally purchased and physically own, and you will not hold the developer responsible when your emulators act up because you chose the wrong configuration settings.")

                    section("1. DISCLAIMER OF AFFILIATION AND ENDORSEMENT", "This Software is an independent, unofficial utility. The developer of this Software is strictly independent and is NOT affiliated, associated, authorized, endorsed by, or in any way officially connected with Nintendo Co., Ltd., Nintendo of America, Inc., or any of their subsidiaries, affiliates, or licensors. All registered trademarks, including but not limited to 'Nintendo', '3DS', 'CTR', and 'Citra', are the exclusive property of their respective owners. The use of these names is for interoperability and descriptive purposes only and does not imply any association or endorsement.")

                    section("2. STRICT PROHIBITION OF PIRACY AND COPYRIGHT INFRINGEMENT", "This Software is designed solely for the purpose of personal data archival, format shifting, and interoperability of legally obtained, physically owned game media. \n\n(a) You explicitly represent and warrant that any and all files (including ROMs, CIAs, CCIs, CXIs, DLCs, and Updates) processed through this Software have been legally dumped directly from hardware or media that you legally purchased and own.\n(b) You shall not use this Software to process, decrypt, distribute, or otherwise interact with unauthorized, pirated, or illegally downloaded copyrighted material.\n(c) The developer strictly condemns software piracy. The developer shall not be held responsible for your actions should you choose to violate international copyright laws.")

                    section("3. THIRD-PARTY COMPONENTS AND LICENSES", "This Software utilizes third-party command-line utilities (including but not limited to ctrtool, makerom, and ctrdecrypt) which are provided under their respective open-source licenses (such as the MIT License or GNU General Public License). These tools are executed in a sandbox environment and their respective licenses apply to their usage. The developer claims no ownership over these specific external binary components.")

                    section("4. IMPOSSIBILITY OF CIA REPACKAGING", "The developer expressly declines to offer the ability to output encrypted .cia containers. The mathematical and cryptographic reality is that generating a valid CIA container requires Nintendo's RSA Private Keys. Unless you are planning on personally breaking into Nintendo Headquarters in Kyoto, bypassing their biometric security, and stealing their internal signing servers, any CIA you generate would be universally rejected by standard hardware and emulators anyway. Therefore, Smelt outputs .cci or .3ds formats exclusively.")

                    section("5. MIT LICENSE & DISCLAIMER OF WARRANTY", "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. \n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.")

                    section("6. LIMITATION OF LIABILITY", "IN NO EVENT SHALL THE AUTHORS, DEVELOPERS, OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. \n\nUnder no circumstances shall the developer be liable for any direct, indirect, incidental, special, exemplary, or consequential damages (including, but not limited to, procurement of substitute goods or services; loss of use, data, or profits; hardware failure; thermal damage to your machine; or business interruption) however caused and on any theory of liability, whether in contract, strict liability, or tort (including negligence or otherwise) arising in any way out of the use of this Software, even if advised of the possibility of such damage.")

                    section("7. INDEMNIFICATION", "You agree to indemnify, defend, and hold harmless the developer from and against any and all claims, liabilities, damages, losses, costs, expenses, or fees (including reasonable attorneys' fees) that arise from your violation of this EULA or your unauthorized use of the Software. Should your actions attract legal scrutiny or litigation, you assume sole and absolute responsibility.")

                    section("8. SEVERABILITY", "If any provision of this EULA is held to be unenforceable or invalid, such provision will be changed and interpreted to accomplish the objectives of such provision to the greatest extent possible under applicable law, and the remaining provisions will continue in full force and effect.")

                    Divider().background(palette.border).padding(.vertical, 8)

                    Toggle(isOn: $checkbox) {
                        Text("I certify that I have read the terms and agree to be bound by them.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.textPrimary)
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(20)
            }
            .background(palette.fieldFill.opacity(0.6))
            .cornerRadius(12)
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Text("Disagree & Exit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.chipFill))
                }
                .buttonStyle(.plain)

                Button(action: onAgree) {
                    Text("Agree & Open")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(checkbox ? palette.onAccent : palette.textFaint)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(checkbox ? Palette.green : palette.chipFill))
                }
                .buttonStyle(.plain)
                .disabled(!checkbox)
            }
            .padding(24)
        }
        .frame(maxWidth: 720)
        .frame(maxHeight: 560)
        .background(palette.licenseFill)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .padding(32)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Palette.blue)
            bodyText(body, opacity: true)
        }
    }

    private func bodyText(_ text: String, opacity: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(opacity ? palette.textSecondary : palette.textPrimary.opacity(0.85))
    }
}
