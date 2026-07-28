#include "ui_settings.h"

#include <QSettings>

QUrl UiSettings::dialogFolder(const QString &key) const
{
    if (key.isEmpty())
        return QUrl();
    QSettings s;
    return s.value(QStringLiteral("dialogFolders/") + key).toUrl();
}

void UiSettings::setDialogFolder(const QString &key, const QUrl &folder)
{
    if (key.isEmpty() || folder.isEmpty())
        return;
    QSettings s;
    s.setValue(QStringLiteral("dialogFolders/") + key, folder);
}

QString UiSettings::theme() const
{
    QSettings s;
    return s.value(QStringLiteral("appearance/theme"), QStringLiteral("dark")).toString();
}

void UiSettings::setTheme(const QString &t)
{
    if (t == theme())
        return;
    QSettings s;
    s.setValue(QStringLiteral("appearance/theme"), t);
    emit themeChanged();
}

QString UiSettings::caseColor() const
{
    QSettings s;
    return s.value(QStringLiteral("appearance/caseColor"), QStringLiteral("white")).toString();
}

void UiSettings::setCaseColor(const QString &c)
{
    if (c == caseColor())
        return;
    QSettings s;
    s.setValue(QStringLiteral("appearance/caseColor"), c);
    emit caseColorChanged();
}

QString UiSettings::accent() const
{
    QSettings s;
    return s.value(QStringLiteral("appearance/accent"), QStringLiteral("green")).toString();
}

void UiSettings::setAccent(const QString &a)
{
    if (a == accent())
        return;
    QSettings s;
    s.setValue(QStringLiteral("appearance/accent"), a);
    emit accentChanged();
}

bool UiSettings::guidedEspPending() const
{
    QSettings s;
    return s.value(QStringLiteral("setup/guidedEspPending"), false).toBool();
}

void UiSettings::setGuidedEspPending(bool v)
{
    if (v == guidedEspPending())
        return;
    QSettings s;
    s.setValue(QStringLiteral("setup/guidedEspPending"), v);
    emit guidedEspPendingChanged();
}
