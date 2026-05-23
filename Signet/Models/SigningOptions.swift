import Foundation

struct SigningOptions {
    var customBundleID: String = ""
    var customAppName: String = ""
    var customVersion: String = ""
    var customIconData: Data? = nil

    var hasBundleIDOverride: Bool { !customBundleID.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasAppNameOverride: Bool  { !customAppName.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasVersionOverride: Bool  { !customVersion.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasIconOverride: Bool     { customIconData != nil }
}
