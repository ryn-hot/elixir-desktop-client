#pragma once

#include <QString>

struct MediaItem {
    QString id;
    QString title;
    QString type;
    int year = 0;
    QString updatedAt;
    int runtimeSeconds = 0;
    QString posterUrl;
    QString backdropUrl;
    QString overview;
    double progress = 0.0;
};
