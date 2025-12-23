#pragma once

#include <MpvQt/mpvabstractitem.h>

class MpvItem : public MpvAbstractItem {
    Q_OBJECT

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
};
