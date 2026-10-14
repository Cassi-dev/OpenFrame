#pragma once

#include "Effects.h"

#include <QVariantList>

namespace of {

/// Estilos prontos de texto, usados no painel Texto e no inspetor (o
/// `TextStylePreset` do app Swift).
namespace TextPresets {
/// { value, title } de cada estilo, na ordem dos cartões.
QVariantList list();
/// Aplica o estilo mantendo fonte, tamanho, posição, alinhamento e largura.
TextStyle applied(const QString &preset, const TextStyle &old);
} // namespace TextPresets

} // namespace of
