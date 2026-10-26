import Foundation

/// A small pure Swift SHA-256 used only for stable non-secret local identifiers. Keeping it in
/// Domain preserves that module's Foundation-only dependency rule.
enum StableSHA256 {
    private static let initial: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
        0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]

    private static let constants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1,
        0x923f_82a4, 0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786,
        0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147,
        0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
        0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a,
        0x5b9c_ca4f, 0x682e_6ff3, 0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    static func digest(_ data: Data) -> [UInt8] {
        let message = padded(data)
        var hash = initial
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            compress(schedule(message, chunkStart: chunkStart), into: &hash)
        }
        return hash.flatMap { word in
            (0..<4).reversed().map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
        }
    }

    private static func padded(_ data: Data) -> [UInt8] {
        var message = Array(data)
        let bitCount = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        message.append(
            contentsOf: (0..<8).reversed().map {
                UInt8(truncatingIfNeeded: bitCount >> ($0 * 8))
            })
        return message
    }

    private static func schedule(_ message: [UInt8], chunkStart: Int) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let start = chunkStart + index * 4
            words[index] = message[start..<(start + 4)].reduce(0) {
                ($0 << 8) | UInt32($1)
            }
        }
        for index in 16..<64 {
            let sigmaZero =
                rotateRight(words[index - 15], by: 7)
                ^ rotateRight(words[index - 15], by: 18) ^ (words[index - 15] >> 3)
            let sigmaOne =
                rotateRight(words[index - 2], by: 17)
                ^ rotateRight(words[index - 2], by: 19) ^ (words[index - 2] >> 10)
            words[index] = words[index - 16] &+ sigmaZero &+ words[index - 7] &+ sigmaOne
        }
        return words
    }

    private static func compress(_ words: [UInt32], into hash: inout [UInt32]) {
        var state = hash
        for index in 0..<64 {
            let sumOne =
                rotateRight(state[4], by: 6) ^ rotateRight(state[4], by: 11)
                ^ rotateRight(state[4], by: 25)
            let choice = (state[4] & state[5]) ^ ((~state[4]) & state[6])
            let temporaryOne =
                state[7] &+ sumOne &+ choice &+ constants[index] &+ words[index]
            let sumZero =
                rotateRight(state[0], by: 2) ^ rotateRight(state[0], by: 13)
                ^ rotateRight(state[0], by: 22)
            let majority =
                (state[0] & state[1]) ^ (state[0] & state[2]) ^ (state[1] & state[2])
            let temporaryTwo = sumZero &+ majority
            state = [
                temporaryOne &+ temporaryTwo, state[0], state[1], state[2],
                state[3] &+ temporaryOne, state[4], state[5], state[6],
            ]
        }
        for index in hash.indices {
            hash[index] &+= state[index]
        }
    }

    private static func rotateRight(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
