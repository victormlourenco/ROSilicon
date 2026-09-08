import Foundation
@testable import ROSilicon

/// A PE file with just enough in it for the wintrust patch to find its way:
/// one section, an export table naming the functions, and a recognisable body
/// for each. Built here rather than checked in as a fixture, so a test can bend
/// any one field and see what the parser makes of it.
struct SyntheticDLL {
    var machine = WintrustPatch.Machine.i386.rawValue
    /// 0x10B for PE32, 0x20B for PE32+.
    var optionalMagic: UInt16 = 0x10B
    var exportNames = WintrustPatch.exports
    /// Names whose entry points into the export directory rather than at code,
    /// which is what a forwarded export looks like.
    var forwarded: Set<String> = []

    /// What an unpatched entry point looks like: push ebp; mov ebp,esp; sub esp,8.
    static let originalBody: [UInt8] = [0x55, 0x89, 0xE5, 0x83, 0xEC, 0x08]

    private let peOffset = 0x80
    private let sectionRVA: UInt32 = 0x1000
    private let sectionFileOffset: UInt32 = 0x200
    private let sectionSize: UInt32 = 0x1000
    private let exportRVA: UInt32 = 0x1100
    private let exportSize: UInt32 = 0x100
    private let functionsRVA: UInt32 = 0x1140
    private let namesRVA: UInt32 = 0x1150
    private let ordinalsRVA: UInt32 = 0x1160
    private let stringsRVA: UInt32 = 0x1170

    // MARK: - Where things landed

    func fileOffset(ofRVA rva: UInt32) -> Int {
        Int(sectionFileOffset) + Int(rva) - Int(sectionRVA)
    }

    /// The code RVA of the nth export. Well clear of the export directory, so
    /// none of them reads as forwarded.
    func bodyRVA(_ index: Int) -> UInt32 { sectionRVA + UInt32(0x20 * index) }

    func bodyOffset(_ index: Int) -> Int { fileOffset(ofRVA: bodyRVA(index)) }

    /// The bytes of the nth entry point as they stand in `data`.
    func body(_ index: Int, in data: Data, count: Int) -> [UInt8] {
        let start = bodyOffset(index)
        return Array(data[start..<start + count])
    }

    // MARK: - The file

    func data() -> Data {
        var data = Data(count: Int(sectionFileOffset + sectionSize))

        data[0] = 0x4D                                   // 'M'
        data[1] = 0x5A                                   // 'Z'
        data.write(UInt32(peOffset), at: 0x3C)

        data[peOffset] = 0x50                            // 'P'
        data[peOffset + 1] = 0x45                        // 'E'
        data.write(machine, at: peOffset + 4)
        data.write(UInt16(1), at: peOffset + 6)          // one section

        let optionalSize: UInt16 = optionalMagic == 0x20B ? 240 : 224
        data.write(optionalSize, at: peOffset + 20)

        let optional = peOffset + 24
        data.write(optionalMagic, at: optional)
        let dataDirectory = optional + (optionalMagic == 0x20B ? 112 : 96)
        data.write(exportRVA, at: dataDirectory)
        data.write(exportSize, at: dataDirectory + 4)

        let section = optional + Int(optionalSize)
        data.replaceSubrange(section..<section + 5, with: Array(".text".utf8))
        data.write(sectionSize, at: section + 8)         // virtual size
        data.write(sectionRVA, at: section + 12)
        data.write(sectionSize, at: section + 16)        // raw size
        data.write(sectionFileOffset, at: section + 20)

        let directory = fileOffset(ofRVA: exportRVA)
        data.write(UInt32(exportNames.count), at: directory + 24)
        data.write(functionsRVA, at: directory + 28)
        data.write(namesRVA, at: directory + 32)
        data.write(ordinalsRVA, at: directory + 36)

        for (index, name) in exportNames.enumerated() {
            let start = bodyOffset(index)
            data.replaceSubrange(
                start..<start + Self.originalBody.count, with: Self.originalBody)

            // A forwarded export's "code" points back into the export data.
            let entry = forwarded.contains(name) ? exportRVA + 8 : bodyRVA(index)
            data.write(entry, at: fileOffset(ofRVA: functionsRVA) + 4 * index)

            let nameRVA = stringsRVA + UInt32(0x20 * index)
            data.write(nameRVA, at: fileOffset(ofRVA: namesRVA) + 4 * index)
            data.write(UInt16(index), at: fileOffset(ofRVA: ordinalsRVA) + 2 * index)

            let text = Array(name.utf8)
            let at = fileOffset(ofRVA: nameRVA)
            data.replaceSubrange(at..<at + text.count, with: text)
        }
        return data
    }
}

private extension Data {
    mutating func write(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8 & 0xFF)
    }

    mutating func write(_ value: UInt32, at offset: Int) {
        for byte in 0..<4 { self[offset + byte] = UInt8(value >> (8 * byte) & 0xFF) }
    }
}
