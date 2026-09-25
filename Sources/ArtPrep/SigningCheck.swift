import Foundation
import Security

/// Restricts the updater to released Kindly Ops Developer ID builds.
enum SigningCheck {
    static func isDeveloperIDSigned(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess,
            let code
        else { return false }
        let text =
            "anchor apple generic"
            + " and certificate leaf[subject.OU] = \"K5U72ZNJ2W\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecStaticCodeCheckValidity(
            code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}
