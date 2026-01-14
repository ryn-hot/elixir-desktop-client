#pragma once

#include <QString>
#include <QStringList>

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
    QStringList genres;
    double progress = 0.0;
};
