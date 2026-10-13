#pragma once

#include <QList>
#include <QString>
#include <QStringView>
#include <optional>
#include <span>

namespace of {

/// Chaves dos enums no JSON (iguais aos `rawValue` da versão Swift), na ordem
/// dos valores. Cada enum especializa `enumKeys`.
template <typename E>
std::span<const char *const> enumKeys();

template <typename E>
QString enumKey(E value)
{
    return QString::fromLatin1(enumKeys<E>()[size_t(value)]);
}

template <typename E>
std::optional<E> enumFromKey(QStringView key)
{
    const auto keys = enumKeys<E>();
    for (size_t i = 0; i < keys.size(); ++i)
        if (key == QLatin1StringView(keys[i]))
            return E(i);
    return std::nullopt;
}

template <typename E>
QList<E> allCases()
{
    QList<E> all;
    for (size_t i = 0; i < enumKeys<E>().size(); ++i)
        all.append(E(i));
    return all;
}

#define OF_ENUM_KEYS(Type, ...)                                                                   \
    template <>                                                                                   \
    inline std::span<const char *const> enumKeys<Type>()                                          \
    {                                                                                             \
        static constexpr const char *keys[] = {__VA_ARGS__};                                      \
        return keys;                                                                              \
    }

} // namespace of
