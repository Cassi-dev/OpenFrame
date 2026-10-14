#pragma once

#include <QImage>

// Uso interno do núcleo: vídeo HDR (BT.2100 HLG ou PQ) → SDR sRGB, como o
// macOS mostra esses arquivos (medido em qt/tests/tools/hdr).

namespace of::ToneMap {

enum class Transfer { Sdr, Hlg, Pq };

/// Converte um quadro RGB BT.2020 com a curva `transfer` (`Format_RGBA64`,
/// sinal 0…1) em sRGB 8 bits opaco (`Format_ARGB32_Premultiplied`):
/// - HLG: luz de cena pelo HLG inverso, com o pico do HLG no branco SDR e a
///   curva aplicada ao maior canal (`L = E·max(E)^(γ−1)`, γ = 0,85);
/// - PQ: luz em nits sobre o branco de referência de 203 nits (BT.2408), com
///   o joelho da EETF do BT.2390 (fonte até 1000 nits) na luminância;
/// - depois, primárias 2020 → 709 em luz linear, limite a 0…1 e curva sRGB.
QImage toSdr(const QImage &rgb2020, Transfer transfer);

} // namespace of::ToneMap
