import ResetRadarUI
import Testing

@Suite struct AccountPaletteTests {
    @Test func stableGlobalNumbersChooseTheApprovedFamilies() {
        #expect(AccountPalette(accountNumber: 1).family == .lavender)
        #expect(AccountPalette(accountNumber: 2).family == .mint)
        #expect(AccountPalette(accountNumber: 3).family == .peach)
    }

    @Test func everyPaletteAppearanceHasTextContrast() {
        for number in 1...3 {
            let palette = AccountPalette(accountNumber: number)
            for appearance in [
                AccountPaletteAppearance.light, .lightIncreased, .dark, .darkIncreased,
            ] {
                #expect(
                    palette.surface(appearance).contrastRatio(
                        with: palette.foreground(appearance)) >= 4.5)
            }
        }
    }
}
