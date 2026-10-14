#pragma once

#include "ExportSettings.h"
#include "Project.h"

#include <QObject>
#include <memory>

namespace of {

/// Exporta o projeto para um arquivo, como o Exporter do Swift: render de cada
/// quadro (Renderer) + mixagem (AudioMixer) → MediaWriter. H.264/HEVC/ProRes
/// (ProRes só em MOV) com AAC, ou só o áudio em M4A; bitrate, fps e quadros-chave
/// do `ExportSettings`; marcas de cor BT.709.
///
/// Roda numa thread de trabalho; os sinais chegam na thread do Exporter.
class Exporter : public QObject
{
    Q_OBJECT

public:
    explicit Exporter(QObject *parent = nullptr);
    /// Cancela e espera a exportação em andamento.
    ~Exporter() override;

    /// Começa (ignorado se já houver uma em andamento). Configuração inválida
    /// termina logo com `finished(false, mensagem)`.
    void start(const Project &project, const ExportSettings &settings, const QString &path);
    /// Interrompe; termina com `finished(false, "")` e apaga o arquivo parcial.
    void cancel();
    bool isRunning() const;

signals:
    /// 0…1, sempre crescente; 1 no fim.
    void progress(double fraction);
    /// Cancelado = `ok` falso com `error` vazio.
    void finished(bool ok, const QString &error);

private:
    struct Impl;
    std::unique_ptr<Impl> d;
};

} // namespace of
