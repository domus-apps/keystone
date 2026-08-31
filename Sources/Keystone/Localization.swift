import Foundation

/* UI strings pass through here: the English source text is the key, so a
   missing translation (or a language Keystone doesn't ship) falls back to
   English by construction. Translations live in
   Resources/<lang>.lproj/Localizable.strings inside the SPM resource
   bundle, which follows the user's system language. */
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
