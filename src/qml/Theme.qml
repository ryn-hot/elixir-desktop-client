pragma Singleton
import QtQuick 6.5

QtObject {
    property color backgroundDark: "#050509"
    property color backgroundMid: "#0B0E14"
    property color backgroundCard: "#11141B"
    property color backgroundCardRaised: "#171B25"
    property color accent: "#FF7A2F"
    property color accentSoft: "#FF7A2F40"
    property color textPrimary: "#F5F6FA"
    property color textSecondary: "#B4B8C2"
    property color textMuted: "#7A7F8A"
    property color border: "#222836"

    property string fontDisplay: "Sora"
    property string fontBody: "Sora"

    property int radiusSmall: 8
    property int radiusMedium: 12
    property int radiusLarge: 18

    property int spacingSmall: 6
    property int spacingMedium: 12
    property int spacingLarge: 20
    property int spacingXLarge: 32
}
