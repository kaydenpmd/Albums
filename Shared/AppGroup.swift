import Foundation
import os

/// The App Group the app and its share extension both open, so an album saved
/// from the share sheet lands in the same library the app shows.
///
/// Its name isn't fixed. The build asks for `group.com.local.albums`, but
/// SideStore re-signs under the installer's own team and renames it to
/// `group.com.local.albums.<TEAMID>` (`adjustedGroupIdentifier` in SideStore's
/// FetchProvisioningProfilesOperation.swift, read 24 Oct 2026). Nothing in
/// Info.plist is updated to say so: the new name exists only in the code
/// signature. So this reads the signature, the way SideStore finds its own
/// group (`Bundle.appGroups` in its Bundle+AltStore.swift).
enum AppGroup {
    private static let log = Logger(subsystem: "com.local.albums", category: "storage")

    /// The group as built, from Info.plist (project.yml sets it).
    static let declaredIdentifier: String =
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.com.local.albums"

    /// The group iOS will actually open for this install, or nil when none of
    /// the candidates works.
    static let identifier: String? = {
        let tried = AppGroup.candidates()
        for candidate in tried where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
            AppGroup.log.notice("using app group \(candidate, privacy: .public)")
            return candidate
        }
        AppGroup.log.error("no usable app group; tried \(tried.joined(separator: ", "), privacy: .public). The library is private to this process, so albums shared from other apps won't reach the app.")
        return nil
    }()

    /// Root of the shared container, or this process's own Application Support
    /// folder when there is no group (see `isShared`).
    static let containerURL: URL = {
        if let group = AppGroup.identifier, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return url
        }
        return URL.applicationSupportDirectory
    }()

    /// False when the app and the share extension can't see each other's files.
    /// Said on screen rather than only logged: the failure otherwise looks like
    /// the share sheet saving albums into nowhere.
    static var isShared: Bool { identifier != nil }

    /// Best first: what the signature says, then SideStore's renaming worked out
    /// from the bundle ID, then the name as built.
    private static func candidates() -> [String] {
        let signed = CodeSignature.appGroups()
        var result = signed.filter { $0.hasPrefix(declaredIdentifier) } + signed.filter { !$0.hasPrefix(declaredIdentifier) }
        if signed.isEmpty {
            log.notice("no app groups in this binary's code signature")
        }

        // SideStore renames the app `com.local.albums.<TEAMID>` and the extension
        // `com.local.albums.<TEAMID>.ShareExtension`, so the team ID is the
        // component after the bundle ID as built.
        let baseBundleID = String(declaredIdentifier.dropFirst("group.".count))
        if let bundleID = Bundle.main.bundleIdentifier, bundleID.hasPrefix(baseBundleID + "."),
           let teamID = bundleID.dropFirst(baseBundleID.count + 1).split(separator: ".").first {
            result.append("\(declaredIdentifier).\(teamID)")
        }
        result.append(declaredIdentifier)

        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }
}

/// Reads the entitlements embedded in this process's own code signature.
///
/// The executable is a Mach-O file (or a fat file holding several). Its
/// `LC_CODE_SIGNATURE` load command points at a SuperBlob, whose index lists
/// the signature's parts; the one with magic 0xFADE7171 is the entitlements as
/// an XML plist. Multi-byte fields in the Mach-O header are little-endian on
/// arm64, and everything inside the signature is big-endian.
enum CodeSignature {
    private static let log = Logger(subsystem: "com.local.albums", category: "storage")

    static func appGroups() -> [String] {
        entitlements()?["com.apple.security.application-groups"] as? [String] ?? []
    }

    static func entitlements() -> [String: Any]? {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: .alwaysMapped)
        else {
            log.error("couldn't read this process's executable to find its entitlements")
            return nil
        }
        guard let sliceStart = arm64SliceOffset(in: data) else {
            log.error("executable isn't a 64-bit Mach-O file this can read")
            return nil
        }
        guard let plist = entitlementsPlist(in: data, sliceStart: sliceStart) else {
            log.notice("executable has no embedded entitlements")
            return nil
        }
        guard let entitlements = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            log.error("embedded entitlements aren't a readable plist")
            return nil
        }
        return entitlements
    }

    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagic64: UInt32 = 0xCAFE_BABF
    private static let machOMagic64: UInt32 = 0xFEED_FACF
    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let loadCommandCodeSignature: UInt32 = 0x1D
    private static let superBlobMagic: UInt32 = 0xFADE_0CC0
    private static let entitlementsBlobMagic: UInt32 = 0xFADE_7171

    /// Where the arm64 Mach-O starts: 0 for a thin file, the arm64 slice's offset in a fat one.
    private static func arm64SliceOffset(in data: Data) -> Int? {
        guard let magic = data.uint32(at: 0, bigEndian: true) else { return nil }
        if magic == fatMagic || magic == fatMagic64 {
            guard let count = data.uint32(at: 4, bigEndian: true) else { return nil }
            let entrySize = magic == fatMagic64 ? 32 : 20
            for index in 0..<Int(count) {
                let entry = 8 + index * entrySize
                guard data.uint32(at: entry, bigEndian: true) == cpuTypeARM64 else { continue }
                if magic == fatMagic64 {
                    return data.uint64(at: entry + 8, bigEndian: true).map { Int($0) }
                }
                return data.uint32(at: entry + 8, bigEndian: true).map { Int($0) }
            }
            return nil
        }
        return data.uint32(at: 0, bigEndian: false) == machOMagic64 ? 0 : nil
    }

    private static func entitlementsPlist(in data: Data, sliceStart: Int) -> Data? {
        // mach_header_64 is 32 bytes; ncmds is at offset 16.
        guard let commandCount = data.uint32(at: sliceStart + 16, bigEndian: false) else { return nil }
        var command = sliceStart + 32
        for _ in 0..<commandCount {
            guard let type = data.uint32(at: command, bigEndian: false),
                  let size = data.uint32(at: command + 4, bigEndian: false), size >= 8
            else { return nil }
            if type == loadCommandCodeSignature {
                // linkedit_data_command: cmd, cmdsize, dataoff, datasize.
                guard let offset = data.uint32(at: command + 8, bigEndian: false) else { return nil }
                return entitlementsBlob(in: data, superBlobStart: sliceStart + Int(offset))
            }
            command += Int(size)
        }
        return nil
    }

    private static func entitlementsBlob(in data: Data, superBlobStart start: Int) -> Data? {
        guard data.uint32(at: start, bigEndian: true) == superBlobMagic,
              let count = data.uint32(at: start + 8, bigEndian: true)
        else { return nil }
        for index in 0..<Int(count) {
            // Each index entry is (type, offset from the SuperBlob's start).
            guard let offset = data.uint32(at: start + 12 + index * 8 + 4, bigEndian: true) else { return nil }
            let blob = start + Int(offset)
            guard data.uint32(at: blob, bigEndian: true) == entitlementsBlobMagic,
                  let length = data.uint32(at: blob + 4, bigEndian: true), length > 8,
                  blob + Int(length) <= data.count
            else { continue }
            return data.subdata(in: (blob + 8)..<(blob + Int(length)))
        }
        return nil
    }
}

private extension Data {
    func uint32(at offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let raw = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
    }

    func uint64(at offset: Int, bigEndian: Bool) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        let raw = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        return bigEndian ? UInt64(bigEndian: raw) : UInt64(littleEndian: raw)
    }
}
