// Signs release archives so installed copies of Grabbit can verify an update really came from
// the maintainer before installing it (Ed25519, via CryptoKit).
//
//   swift Scripts/sign_update.swift keygen        create the private key (once) and print the public key
//   swift Scripts/sign_update.swift public        print the public key for an existing private key
//   swift Scripts/sign_update.swift sign <file>   print a base64 signature for <file>
//
// The private key lives outside the repository in ~/.config/ytdown/update_signing_key.
// Keep a backup: without it, existing installs will refuse future updates.
import CryptoKit
import Foundation

let keyURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/ytdown/update_signing_key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyURL, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("No signing key at \(keyURL.path). Run: swift Scripts/sign_update.swift keygen") }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyURL.path) { fail("A key already exists at \(keyURL.path); not overwriting it.") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = args.dropFirst().first, let data = FileManager.default.contents(atPath: path) else { fail("usage: sign <file>") }
    print(try loadKey().signature(for: data).base64EncodedString())
default:
    fail("usage: sign_update.swift keygen | public | sign <file>")
}
