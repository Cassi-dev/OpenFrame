#pragma once

#include "Effects.h"
#include "LinearImage.h"

namespace of {

/// Ajustes, filtros e efeitos aplicados à imagem de um clipe, antes do
/// posicionamento no canvas, com os mesmos parâmetros do ImageEffects Swift.
/// `k` = altura do canvas / 1080 × escala da imagem de trabalho, para que raios
/// de desfoque etc. tenham o mesmo aspecto em qualquer resolução.
///
/// Como no Core Image, tudo é calculado em luz linear; os passos que o Core
/// Image faz em sRGB (curva de tons, vinheta) também são feitos em sRGB. Os
/// números foram conferidos contra o Swift (fixtures/efeitos.json).
namespace ImageEffects {
void adjust(LinearImage &, const Adjust &, double k, double time);
void filter(LinearImage &, const FilterSetting &);
void effects(LinearImage &, const QList<VideoEffect> &, double k, double time);

/// Deslocamento (em unidades normalizadas do canvas) e escala dos efeitos geométricos.
struct Geometry {
    double dx = 0;
    double dy = 0;
    double scale = 1;
};
Geometry geometry(const QList<VideoEffect> &, double time);

/// Brilho do CIColorControls (soma em luz linear), usado no fundo desfocado.
void brightness(LinearImage &, double amount);
} // namespace ImageEffects

} // namespace of
