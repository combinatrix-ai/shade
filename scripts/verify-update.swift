import Foundation
import CryptoKit
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let plist = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as! [String: Any]
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let signatureText = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
let regex = try NSRegularExpression(pattern: "sparkle:edSignature=\"([^\"]+)\"")
let range = NSRange(signatureText.startIndex..., in: signatureText)
let match = regex.firstMatch(in: signatureText, range: range)!
let sig = Data(base64Encoded: String(signatureText[Range(match.range(at: 1), in: signatureText)!]))!
guard publicKey.isValidSignature(sig, for: archive) else { fatalError("Update signature does not match embedded public key") }
var tampered = sig
tampered[0] ^= 1
guard !publicKey.isValidSignature(tampered, for: archive) else { fatalError("Tampered signature accepted") }
print("Embedded update key verified; tampered signature rejected")
