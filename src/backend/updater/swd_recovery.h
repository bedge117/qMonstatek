/*
 * swd_recovery.h — SWD recovery tools via OpenOCD
 *
 * Wraps OpenOCD to provide flash recovery, bank swap, verify,
 * clone, and status read operations for the M1 using a debug
 * probe (Raspberry Pi Pico with CMSIS-DAP or ST-Link V2).
 */

#ifndef SWD_RECOVERY_H
#define SWD_RECOVERY_H

#include <QObject>
#include <QProcess>
#include <QString>

class SwdRecovery : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool running READ isRunning NOTIFY runningChanged)
    Q_PROPERTY(int  progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString outputLog READ outputLog NOTIFY outputLogChanged)
    Q_PROPERTY(int probeType READ probeType WRITE setProbeType NOTIFY probeTypeChanged)

public:
    explicit SwdRecovery(QObject *parent = nullptr);
    ~SwdRecovery() override;

    enum ProbeType { PicoCmsisDap = 0, StLinkV2 = 1 };
    Q_ENUM(ProbeType)

    bool    isRunning()     const { return m_running; }
    int     progress()      const { return m_progress; }
    QString statusMessage() const { return m_statusMessage; }
    QString outputLog()     const { return m_outputLog; }
    int     probeType()     const { return m_probeType; }
    void    setProbeType(int type);

    Q_INVOKABLE void recoveryFlash(const QString &binFilePath);
    Q_INVOKABLE void swapBank();
    Q_INVOKABLE void verifyBank2(const QString &binFilePath);
    Q_INVOKABLE void cloneBank1ToBank2();
    Q_INVOKABLE void readStatus();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clearLog();
    Q_INVOKABLE bool isOpenOcdAvailable();
    Q_INVOKABLE QString openOcdLocation();

signals:
    void runningChanged(bool running);
    void progressChanged(int percent);
    void statusMessageChanged(const QString &msg);
    void outputLogChanged();
    void probeTypeChanged(int type);
    void operationComplete(const QString &message);
    void operationError(const QString &message);

private slots:
    void onProcessOutput();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    void    runOpenOcd(const QString &commands, const QString &opName);
    void    runCubeProgrammer(const QStringList &args, const QString &opName);
    void    resolveOpenOcdPaths();
    void    resolveCubeProgrammerPath();
    void    probeVersion();
    QString interfaceConfig() const;
    bool    validateSetup(QString &error) const;
    void    setStatus(const QString &msg);
    void    appendLog(const QString &text);

    QProcess *m_process      = nullptr;
    QString   m_ocdPath;
    QString   m_scriptsPath;
    QString   m_ocdVersion;
    QString   m_cubeProgrammerPath;

    bool    m_running        = false;
    int     m_progress       = 0;
    int     m_probeType      = PicoCmsisDap;
    bool    m_pathsResolved  = false;
    bool    m_cubeProgResolved = false;
    bool    m_usingCubeProg  = false;
    QString m_statusMessage;
    QString m_outputLog;
    QString m_currentOp;
};

#endif // SWD_RECOVERY_H
