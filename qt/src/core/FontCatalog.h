#pragma once

#include <QStringList>

namespace of {

/// Famílias e estilos de fonte instalados, para os menus do inspetor.
/// Usa o `QFontDatabase`: precisa de um `QGuiApplication` criado.
namespace FontCatalog {
/// Famílias visíveis (sem as privadas do sistema e as que começam com "."),
/// em ordem alfabética natural ("Font 2" antes de "Font 10").
QStringList families();
/// Estilos de uma família ("Light", "Regular", "Bold Italic"…), do mais fino ao
/// mais grosso, os itálicos depois.
QStringList faces(const QString &family);
/// Ordem natural dos nomes, como o `localizedStandardCompare` do Swift: sem
/// diferenciar maiúsculas e com os números pelo valor ("Font 2" < "Font 10").
/// Negativo, zero ou positivo; é uma ordem fraca estrita em qualquer plataforma
/// (o QCollator do Windows pode falhar e responder "menor" nos dois sentidos).
int naturalCompare(const QString &a, const QString &b);
} // namespace FontCatalog

} // namespace of
