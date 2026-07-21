/*
 * screen_canvas.h — QML item that renders pushed M1 screen frames
 *
 * Frames are delivered by push via setFrame() (wired in QML to
 * M1Device::screenImageReady), so the GUI thread neither pulls through an
 * image provider nor performs any framebuffer conversion — the finished,
 * upscaled QImage arrives ready to blit (COMMS_REBUILD_SPEC §7).
 */

#ifndef SCREEN_CANVAS_H
#define SCREEN_CANVAS_H

#include <QQuickPaintedItem>
#include <QImage>

class ScreenCanvas : public QQuickPaintedItem {
    Q_OBJECT

public:
    explicit ScreenCanvas(QQuickItem *parent = nullptr);

    /* Push a finished (already upscaled) frame; schedules a repaint. */
    Q_INVOKABLE void setFrame(const QImage &image);

    void paint(QPainter *painter) override;

private:
    QImage m_frame;
};

#endif // SCREEN_CANVAS_H
