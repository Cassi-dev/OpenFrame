#pragma once

#include "Project.h"

#include <QImage>

namespace of {

namespace MediaProbe {
/// Se o arquivo é uma mídia que o `probe` aceita (foto, vídeo ou áudio), pela
/// extensão, sem diferenciar maiúsculas (`.MOV` do iPhone).
bool isSupported(const QString &path);
bool isImageExtension(const QString &extension);
bool isAudioExtension(const QString &extension);

/// Lê o arquivo e cria o `Material` correspondente, com as dimensões de
/// exibição (já girado pela matriz do vídeo ou pela orientação EXIF da foto).
/// Erros: "Formato não suportado: <nome>" ou "Não foi possível ler: <nome>".
/// Pode rodar fora da thread principal.
std::optional<Material> probe(const QString &path, QString *error = nullptr);
} // namespace MediaProbe

namespace Images {
/// Foto já orientada (EXIF), convertida para sRGB e pré-multiplicada
/// (`Format_ARGB32_Premultiplied`). `maxSide` > 0 reduz a imagem para caber.
/// Formatos que o Qt não lê (HEIC no Windows/Linux) passam pelo FFmpeg.
QImage load(const QString &path, int maxSide = 0, QString *error = nullptr);
} // namespace Images

} // namespace of
