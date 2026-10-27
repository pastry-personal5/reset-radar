import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTransport
import Testing

@Suite struct ReaderProfileCipherTests {
    private let publisher = PublisherID(data: Data(repeating: 0x23, count: 32))!
    private let reader = ReaderID(data: Data(repeating: 0x45, count: 16))!
    private let key = SecretValue(Data(repeating: 0x67, count: 32))

    @Test func profileNameAcceptsVisibleUnicodeAndEnforcesByteBound() throws {
        #expect(try ReaderProfileName(validating: "민지의 iPhone").value == "민지의 iPhone")
        #expect(throws: ReaderProfileNameError.noVisibleContent) {
            try ReaderProfileName(validating: "   ")
        }
        #expect(throws: ReaderProfileNameError.tooLong) {
            try ReaderProfileName(validating: String(repeating: "a", count: 65))
        }
    }

    @Test func roundTripAuthenticatesIdentityAndRevision() throws {
        let cipher = AESGCMReaderProfileCipher(
            nonceSource: { Data(repeating: 0xAB, count: 12) })
        let header = ReaderProfileHeader(
            publisherID: publisher, readerID: reader, keyVersion: 1, revision: 7)
        let profile = ReaderProfile(
            displayName: try ReaderProfileName(validating: "Work iPhone"), deviceClass: .phone)
        let body = try cipher.seal(profile, header: header, key: key)
        #expect(body.range(of: Data("Work iPhone".utf8)) == nil)
        let opened = try cipher.open(body, expected: header, key: key)
        #expect(opened.header == header)
        #expect(opened.profile == profile)

        let changed = ReaderProfileHeader(
            publisherID: publisher, readerID: reader, keyVersion: 1, revision: 8)
        #expect(throws: ReaderProfileCipherError.authenticationFailed) {
            try cipher.open(body, expected: changed, key: key)
        }
    }
}
