/*
 * app_switcher.h — Locate and hand off to qMonstatek Studio.
 *
 * qMonstatek (classic) manages classic C3 firmware; qMonstatek Studio manages
 * M1OS. They intentionally remain separate applications — a user can run both at
 * once for two different M1 devices. This helper only launches Studio when the
 * user explicitly requests a handoff, preserving the current serial port as a
 * command-line hint.
 */

#ifndef APP_SWITCHER_H
#define APP_SWITCHER_H

#include <QObject>
#include <QString>

class AppSwitcher : public QObject {
    Q_OBJECT

public:
    explicit AppSwitcher(QObject *parent = nullptr);

    Q_INVOKABLE bool studioInstalled() const;
    Q_INVOKABLE QString studioExecutable() const;

    // Starts qMonstatek Studio with --port when a USB M1 is selected, then exits
    // qMonstatek. Returns false and emits launchError if a suitable Studio
    // executable is not present or Windows refuses to start it.
    Q_INVOKABLE bool launchStudioAndQuit(const QString &portName);

signals:
    void launchError(const QString &message);

private:
    QString locateStudio() const;
};

#endif // APP_SWITCHER_H
