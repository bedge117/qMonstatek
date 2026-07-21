/*
 * screen_canvas.cpp — QML item that renders pushed M1 screen frames
 */

#include "screen_canvas.h"
#include <QPainter>

ScreenCanvas::ScreenCanvas(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
}

void ScreenCanvas::setFrame(const QImage &image)
{
    m_frame = image;
    update();
}

void ScreenCanvas::paint(QPainter *painter)
{
    if (m_frame.isNull())
        return;
    // SmoothPixmapTransform is off by default → nearest-neighbor, crisp pixels.
    painter->drawImage(boundingRect(), m_frame);
}
