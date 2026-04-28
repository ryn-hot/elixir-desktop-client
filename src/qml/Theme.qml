pragma Singleton
import QtQuick 6.5

QtObject {
    property color appBg: "#151515"
    property color stageBg: "#191A1D"
    property color sidebarBg: "#101114"
    property color topBarBg: "#0B0C0F"
    property color surface: "#202124"
    property color surfaceRaised: "#292B30"
    property color surfaceHover: "#363941"
    property color panelSoft: "#1B1D21"
    property color borderSubtle: "#34363D"

    property color bgMain: appBg
    property color bgSidebar: sidebarBg
    property color bgCard: surface
    property color accent: "#F2A93B"
    property color accentHover: "#FFC15A"
    property color accentPressed: "#D8901F"
    property color accentDeep: "#A76512"
    property color accentDanger: "#D95F5F"
    property color accentDangerSoft: "#33d86b6b"
    property color accentSuccess: "#4CBF7A"
    property color accentSuccessSoft: "#2a5fbf5a"
    property color accentInfo: "#65A9F5"
    property color accentInfoSoft: "#2a58a6ff"
    property color accentMutedSoft: "#22777777"
    property color textPrimary: "#F2F4F7"
    property color textSecondary: "#B4BAC3"
    property color textMuted: "#7E8794"
    property color textDisabled: "#59616D"
    property color divider: borderSubtle
    property color danger: accentDanger
    property color success: accentSuccess
    property color info: accentInfo

    property int sidebarWidth: 244
    property int topBarHeight: 62
    property int posterWidth: 154
    property int posterHeight: 231
    property int posterLargeWidth: 214
    property int posterLargeHeight: 321
    property int landscapeWidth: 304
    property int landscapeHeight: 171
    property int episodeThumbWidth: 256
    property int episodeThumbHeight: 144
    property int cardSpacing: 24
    property int sectionSpacing: 42

    property int space4: 4
    property int space8: 8
    property int space10: 10
    property int space12: 12
    property int space14: 14
    property int space16: 16
    property int space18: 18
    property int space20: 20
    property int space24: 24
    property int space28: 28
    property int space32: 32
    property int space36: 36
    property int space40: 40
    property int space56: 56

    property int fontHero: 44
    property int fontTitle: 30
    property int fontSection: 13
    property int fontBodySize: 14
    property int fontMeta: 12
    property int fontCaption: 11

    property font headerFont: Qt.font({ family: "Open Sans", pixelSize: 22, weight: Font.Bold })
    property font sectionTitleFont: Qt.font({ family: "Open Sans", pixelSize: 13, weight: Font.Bold, capitalization: Font.AllUppercase })
    property font bodyFont: Qt.font({ family: "Open Sans", pixelSize: 14 })

    property color backgroundDark: bgMain
    property color backgroundMid: bgSidebar
    property color backgroundCard: bgCard
    property color backgroundCardRaised: surfaceRaised
    property color accentSoft: "#40F2A93B"
    property color overlayWeak: "#33000000"
    property color overlayMedium: "#88000000"
    property color overlayStrong: "#CC000000"
    property color border: divider

    property string fontDisplay: "Open Sans"
    property string fontBodyName: "Open Sans"
    property string fontBody: fontBodyName

    property int radiusSmall: 4
    property int radiusMedium: 6
    property int radiusLarge: 8
    property int radius4: 4
    property int radius6: 6
    property int radius8: 8

    property int spacingSmall: 8
    property int spacingMedium: 16
    property int spacingLarge: 24
    property int spacingXLarge: 32

    property int toastDurationMs: 4000
    property int toastFadeMs: 400
}
