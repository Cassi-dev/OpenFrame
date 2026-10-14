#pragma once

#include "Project.h"
#include "VideoDecoder.h"

#include <QCache>
#include <QImage>
#include <QMutex>

namespace of {

/// Desenha um quadro do projeto na CPU, como o FrameRenderer/OpenFrameCompositor
/// do Swift: fundo (preto, cor ou desfoque), faixas de vídeo com ajustes,
/// filtros, efeitos, encaixe × transformação × animação × geometria, opacidade
/// e transições, e por fim os textos. O mesmo renderizador serve ao preview,
/// à exportação e às miniaturas. Thread-safe.
///
/// Trabalha em luz linear (como o Core Image) e devolve sRGB 8 bits opaco
/// (`Format_ARGB32_Premultiplied`).
class Renderer
{
public:
    Renderer();
    ~Renderer();

    /// Renderizador compartilhado (miniaturas, tela inicial).
    static Renderer &shared();

    /// Quadro do instante `t` no tamanho `size` (que define a escala: os
    /// efeitos usam altura/1080).
    QImage render(const Project &project, Micros t, QSize size);

    /// Esquece decodificadores e fotos (ao trocar de projeto).
    void clearCaches();

private:
    struct Impl;
    std::unique_ptr<Impl> d;
};

/// Miniaturas de pré-visualização para a aba de filtros.
namespace EffectPreview {
QImage filtered(const QImage &image, FilterPreset preset);
} // namespace EffectPreview

} // namespace of
