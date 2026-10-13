#pragma once

#include "Project.h"

#include <QByteArray>
#include <QJsonObject>
#include <QString>
#include <optional>

namespace of {

/// Salva e abre projetos `.openframe` (JSON legível, no espírito do
/// `draft_content.json` do CapCut). O formato é o mesmo da versão Swift:
/// chaves em ordem alfabética, enums pelo `rawValue`, UUID em maiúsculas,
/// opcionais nulos omitidos e todos os outros campos gravados. Na leitura, os
/// campos são obrigatórios como no Swift, menos os do `TextStyle`, que ficam com
/// o padrão quando faltam (projetos de versões anteriores).
namespace ProjectStore {
inline const QString fileExtension = QStringLiteral("openframe");

QJsonObject toJson(const Project &);
std::optional<Project> fromJson(const QJsonObject &, QString *error = nullptr);

QByteArray encode(const Project &);
std::optional<Project> decode(const QByteArray &data, QString *error = nullptr);

/// Grava de forma atômica (arquivo temporário + troca).
bool save(const Project &, const QString &path, QString *error = nullptr);
std::optional<Project> load(const QString &path, QString *error = nullptr);

QString uuidString(const QUuid &);
} // namespace ProjectStore

} // namespace of
