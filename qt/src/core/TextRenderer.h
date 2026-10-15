#pragma once

#include "Effects.h"

#include <QCache>
#include <QImage>
#include <QMutex>

namespace of {

/// Rasteriza texto (QTextLayout + contornos dos glifos) e guarda o resultado em
/// cache por conteúdo, estilo, resolução e progresso da animação. Mesmas regras
/// do TextRenderer Swift: contorno só para fora com junção redonda, negrito e
/// itálico sintéticos quando a família não tem esses estilos, sombra única do
/// conjunto letras + contorno + sublinhado, fundo arredondado, espaçamentos,
/// caixa das letras e máquina de escrever. Emoji são desenhados coloridos.
///
/// A imagem sai em sRGB pré-multiplicado, do tamanho do texto mais as margens;
/// quem desenha centraliza-a no ponto do estilo. Thread-safe.
class TextRenderer
{
public:
    static TextRenderer &shared();

    /// Imagem do texto para um canvas `canvas`; `reveal` (0…1) é a fração de
    /// letras visíveis. Nula se o texto estiver vazio.
    QImage image(const TextContent &content, QSize canvas, double reveal = 1);

    /// Caixa das letras aplicada na hora de desenhar.
    static QString cased(const QString &text, TextCase textCase);

    /// Tamanho em pixels da caixa do texto mais o fundo (se ligado), sem as margens de sombra, já com a
    /// palavra-chave, `fitLines` e `balanceLines`. A imagem de `image()` tem o mesmo centro. Vazio se o texto
    /// estiver vazio. O `CanvasLayout` mede num canvas com lado menor 1080.
    std::optional<QSizeF> boxSize(const TextContent &content, QSize canvas);

    /// Largura do texto numa linha só, com a fonte, a caixa e o espaçamento do estilo, para a fonte de
    /// `fontPx` pixels (com os espaços e o espaçamento do fim). Usado pela quebra das legendas.
    double lineWidth(const QString &text, const TextStyle &style, double fontPx);

    /// Texto de cada linha do layout (as quebras automáticas e as de `\n`), sem os espaços das pontas.
    QStringList lineTexts(const TextContent &content, QSize canvas);

private:
    QImage render(const QString &text, const TextStyle &style, const std::optional<WordEmphasis> &emphasis,
                  QSize canvas, int visibleCharacters);

    QMutex m_lock;
    QCache<QString, QImage> m_cache{256};
    QCache<QString, QSizeF> m_sizes{1024};
};

} // namespace of
