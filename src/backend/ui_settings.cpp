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
