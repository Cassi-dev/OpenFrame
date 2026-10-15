#pragma once

#include "Enums.h"

#include <QObject>
#include <QString>
#include <QUrl>

namespace of {

/// Modelos do Whisper oferecidos para as legendas automáticas (formato ggml do whisper.cpp).
enum class WhisperModel {
    Base,
    Small,
    /// large-v3-turbo quantizado em q5_0.
    Turbo
};
OF_ENUM_KEYS(WhisperModel, "base", "small", "turbo")

/// "Rápido", "Equilibrado", "Máxima precisão".
QString displayName(WhisperModel);
/// Nome do arquivo no repositório e na pasta local.
QString fileName(WhisperModel);
qint64 byteSize(WhisperModel);
QUrl downloadUrl(WhisperModel);
/// sha256 em hexadecimal minúsculo.
QString sha256(WhisperModel);
/// Modelo indicado na interface. Nesta versão o whisper roda só na CPU, onde o turbo é lento (10,4 s para
/// 64 s de fala no M5, contra 4,5 s do small, com WER 0,06): o recomendado é o small ("Equilibrado").
WhisperModel recommendedModel();

/// Modelos baixados em `QStandardPaths::AppLocalDataLocation/Models` (a variável de ambiente
/// `OPENFRAME_MODELS_DIR` troca a pasta). O download é o único acesso à rede do app, só quando o usuário pede.
///
/// Etapa 1: `path`, `isInstalled` e `remove` funcionam; `download` ainda termina com erro (o download com
/// retomada e sha256 entra na etapa 3, junto com o whisper).
class ModelStore : public QObject
{
    Q_OBJECT

public:
    explicit ModelStore(const QString &directory, QObject *parent = nullptr);
    /// Pasta padrão (ou a de `OPENFRAME_MODELS_DIR`).
    static ModelStore &shared();
    static QString defaultDirectory();

    QString directory() const { return m_directory; }
    QString path(WhisperModel m) const;
    /// Instalado = o arquivo final existe com o tamanho certo (o sha256 é conferido ao baixar).
    bool isInstalled(WhisperModel m) const;
    /// Baixa para um `.partial`, confere tamanho e sha256 e só então move para o lugar. Retoma o que já veio
    /// quando o servidor permite. Termina com `downloadFinished`.
    void download(WhisperModel m);
    /// Interrompe o download (o parcial fica para retomar); termina com `downloadFinished(m, false, "")`.
    void cancel(WhisperModel m);
    bool isDownloading(WhisperModel m) const;
    /// Apaga o modelo e o parcial.
    bool remove(WhisperModel m, QString *error = nullptr);

signals:
    /// 0…1.
    void downloadProgress(of::WhisperModel model, double fraction);
    /// Cancelado = `ok` falso com `error` vazio.
    void downloadFinished(of::WhisperModel model, bool ok, const QString &error);

private:
    QString m_directory;
};

} // namespace of
