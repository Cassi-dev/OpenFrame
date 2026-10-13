#pragma once

#include "Timing.h"

#include <QHash>
#include <QImage>
#include <QMutex>
#include <QUuid>
#include <list>
#include <memory>

namespace of {

/// Decodifica quadros de um vídeo com busca precisa: `frameAt(t)` devolve o
/// quadro exibido no instante `t` do arquivo (o último com início ≤ t), já
/// orientado pela matriz de exibição e com a proporção de pixel aplicada.
///
/// Cores: YUV → RGB com a matriz e o intervalo marcados no arquivo; sem marca,
/// BT.709 em HD e BT.601 em SD (nunca o 601 fixo do swscale). A saída é sRGB
/// de 8 bits em `Format_ARGB32_Premultiplied`.
///
/// Leituras em sequência (reprodução, exportação) seguem decodificando sem
/// buscar. Não é thread-safe: use um por segmento (veja `DecoderCache`).
class VideoDecoder
{
public:
    static std::unique_ptr<VideoDecoder> open(const QString &path, QString *error = nullptr);
    ~VideoDecoder();

    /// Quadro no instante `t` (microssegundos desde o início do arquivo).
    /// `maxSize` válido reduz o quadro para caber nele (mantendo a proporção).
    /// Imagem nula se o arquivo não tiver quadros.
    QImage frameAt(Micros t, QSize maxSize = {});

    /// Dimensões de exibição (girada e com a proporção de pixel).
    QSize displaySize() const;
    Micros duration() const;
    /// Início do quadro devolvido pela última chamada a `frameAt`.
    Micros lastFrameTime() const;
    /// Quantas buscas (`av_seek_frame`) já foram feitas, para os testes.
    int seekCount() const;

private:
    VideoDecoder();
    struct Impl;
    std::unique_ptr<Impl> d;
};

/// Decodificadores por segmento: cada segmento de vídeo tem o seu, para que
/// dois trechos do mesmo arquivo (ou os dois lados de uma transição) não
/// fiquem buscando um sobre o outro. Guarda os `capacity` usados por último.
class DecoderCache
{
public:
    explicit DecoderCache(int capacity = 16) : m_capacity(capacity) {}

    /// Quadro do segmento `segment` (arquivo `path`) no instante `t` do arquivo.
    /// Thread-safe; chamadas para o mesmo segmento são serializadas.
    QImage frame(const QUuid &segment, const QString &path, Micros t, QSize maxSize = {});
    void clear();

private:
    struct Entry {
        QString path;
        std::unique_ptr<VideoDecoder> decoder;
        std::unique_ptr<QMutex> lock = std::make_unique<QMutex>();
        bool failed = false;
    };
    QMutex m_lock;
    std::list<std::pair<QUuid, std::shared_ptr<Entry>>> m_entries; // mais recente na frente
    int m_capacity;
};

} // namespace of
