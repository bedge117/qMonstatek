#pragma once

#include <QObject>
#include <QUrl>

/*
 * UiSettings — small QSettings-backed store for UI state that should persist
 * across runs (org/app name are set in main.cpp, so QSettings has a real home).
 *
 * Currently used to remember the last-used folder of each file dialog, keyed by
 * a caller-supplied string. Without this, every FileDialog falls back to the OS
 * global "last used" directory, so browsing in one (e.g. Firmware) moves where
 * the next one (e.g. ESP32 / Debug Log) opens. Giving each dialog its own key
 * keeps them independent — and remembered between sessions.
 */
class UiSettings : public QObject {
    Q_OBJECT
    /* App theme: "dark" (default) or "light". Persisted across runs. */
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
    /* M1 device-skin case color: white/black/clear/orange/green. Persisted. */
    Q_PROPERTY(QString caseColor READ caseColor WRITE setCaseColor NOTIFY caseColorChanged)
public:
    explicit UiSettings(QObject *parent = nullptr) : QObject(parent) {}

    /* Last folder used by the dialog identified by `key` (empty url if none). */
    Q_INVOKABLE QUrl dialogFolder(const QString &key) const;
    Q_INVOKABLE void setDialogFolder(const QString &key, const QUrl &folder);

    QString theme() const;
    void setTheme(const QString &t);

    QString caseColor() const;
    void setCaseColor(const QString &c);

signals:
    void themeChanged();
    void caseColorChanged();
};
