/*
 * log_model.h — Application log capture model for embedded debug panel
 */

#ifndef LOG_MODEL_H
#define LOG_MODEL_H

#include <QObject>
#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QRecursiveMutex>

class LogModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles { MessageRole = Qt::UserRole + 1 };

    explicit LogModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void clear();
    Q_INVOKABLE QString fullText() const;

    Q_INVOKABLE void append(const QString &line);

signals:
    void countChanged();
    void lineAppended(const QString &line);

private:
    QStringList m_lines;
    mutable QRecursiveMutex m_mutex;
    static constexpr int MAX_LINES = 5000;
};

// Global instance for the Qt message handler
LogModel* globalLogModel();
void setGlobalLogModel(LogModel *model);

#endif // LOG_MODEL_H
