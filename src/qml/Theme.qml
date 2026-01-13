pragma Singleton
import QtQuick 6.5

QtObject {
    // Plex-like Spec Constants
    // Colors
    property color bgMain: "#282a2d"       // Main window background
    property color bgSidebar: "#1f2124"    // Sidebar background
    property color bgCard: "#2c2f33"       // Placeholder for loading cards
    property color accent: "#e5a00d"       // The "Plex Orange"
    property color textPrimary: "#ececec"
    property color textSecondary: "#999999"
    property color divider: "#3e4247"

    // Dimensions
    property int sidebarWidth: 240
    property int topBarHeight: 60
    property int posterWidth: 160
    property int posterHeight: 240
    property int landscapeWidth: 320
    property int landscapeHeight: 180
    property int cardSpacing: 16
    property int sectionSpacing: 40

    // Typography (using Open Sans if available, falling back to system sans-serif)
    property font headerFont: Qt.font({ family: "Open Sans", pixelSize: 22, weight: Font.Bold })
    property font sectionTitleFont: Qt.font({ family: "Open Sans", pixelSize: 13, weight: Font.Bold, capitalization: Font.AllUppercase })
    property font bodyFont: Qt.font({ family: "Open Sans", pixelSize: 14 })

    // Legacy Compatibility (Mapped to new palette)
    property color backgroundDark: bgMain
    property color backgroundMid: bgSidebar
    property color backgroundCard: bgCard
    property color backgroundCardRaised: "#383b40" // Slightly lighter than bgCard
    property color accentSoft: "#40e5a00d" // Transparent orange
    property color textMuted: "#777777"
    property color border: divider

    property string fontDisplay: "Open Sans"
    property string fontBodyName: "Open Sans" // Renamed to avoid conflict with font object

    property int radiusSmall: 4
    property int radiusMedium: 6
    property int radiusLarge: 8

    property int spacingSmall: 8
    property int spacingMedium: 16
    property int spacingLarge: 24
    property int spacingXLarge: 32
}
