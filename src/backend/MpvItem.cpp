#include "backend/MpvItem.h"

MpvItem::MpvItem(QQuickItem *parent)
    : MpvAbstractItem(parent) {
    // Inherit MpvAbstractItem behavior; QML can call getProperty/setPropertyAsync/commandAsync.
}
