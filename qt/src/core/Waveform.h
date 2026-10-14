#pragma once

#include <QList>
#include <QString>

namespace of {

/// Picos de amplitude de um arquivo, para desenhar a forma de onda na timeline.
namespace Waveform {
/// Picos por segundo de mídia; suficiente até o zoom máximo da timeline.
inline constexpr double peaksPerSecond = 50;

/// Lê o áudio inteiro (mixado em mono a 8 kHz) e devolve um pico por
/// intervalo, normalizado entre 0 e 1 pelo maior pico do arquivo. Vazio se o
/// arquivo não tiver áudio. Pode rodar fora da thread principal.
QList<float> peaks(const QString &path, double perSecond = peaksPerSecond, QString *error = nullptr);
} // namespace Waveform

} // namespace of
