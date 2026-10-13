#pragma once

#include "Project.h"

#include <QImage>

namespace of {

/// Miniaturas para a biblioteca de mídia e a timeline.
namespace Thumbnails {
/// Vídeo: `count` quadros em (i + 0,5)/count da duração; foto: uma imagem já
/// orientada; áudio: nenhuma. Cada imagem cabe em `maxSide` × `maxSide`.
/// Pode rodar fora da thread principal.
QList<QImage> frames(const Material &, int count = 10, int maxSide = 240);
} // namespace Thumbnails

} // namespace of
