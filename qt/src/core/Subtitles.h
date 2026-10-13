#pragma once

#include "Project.h"

namespace of {

struct SubtitleCue {
    Micros start = 0;
    Micros end = 0;
    QString text;
    bool operator==(const SubtitleCue &) const = default;
};

/// Leitura e escrita de legendas SubRip (.srt).
namespace SRT {
QList<SubtitleCue> parse(const QString &content);
/// Aceita `HH:MM:SS,mmm` e `HH:MM:SS.mmm` (ignora posicionamento após o horário).
std::optional<Micros> parseTimestamp(const QString &raw);
QString serialize(const QList<SubtitleCue> &cues);
QString timestamp(Micros t);

/// Converte as legendas em segmentos de texto numa faixa nova.
void importCues(const QList<SubtitleCue> &cues, Project &p, const TextStyle &style = {});
/// Coleta todos os segmentos de texto do projeto como legendas.
QList<SubtitleCue> cues(const Project &p);
} // namespace SRT

} // namespace of
