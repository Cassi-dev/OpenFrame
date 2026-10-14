#pragma once

#include <QHash>
#include <QImage>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QString>
#include <QVector>

namespace of {

/// Miniaturas e formas de onda dos materiais do projeto aberto, por id do
/// material. O EditorModel preenche; os itens da timeline e da biblioteca leem.
class MediaCache : public QObject
{
    Q_OBJECT

public:
    static MediaCache *instance();

    /// Picos de áudio por segundo de mídia (o `Waveform.peaksPerSecond` do Swift).
    static constexpr double peaksPerSecond = 50;

    // Leitura também fora da thread principal (prévias dos filtros).
    QList<QImage> thumbnails(const QString &id) const;
    QVector<float> peaks(const QString &id) const;
    bool hasThumbnails(const QString &id) const;
    bool hasPeaks(const QString &id) const;

    void setThumbnails(const QString &id, const QList<QImage> &images);
    void setPeaks(const QString &id, const QVector<float> &peaks);
    void remove(const QString &id);
    void clear();

    /// Quadro atual do preview (já renderizado no tamanho do preview).
    QImage previewFrame() const { return m_frame; }
    void setPreviewFrame(const QImage &frame);

signals:
    void changed(const QString &id);
    void previewFrameChanged();

private:
    QHash<QString, QList<QImage>> m_thumbnails;
    QHash<QString, QVector<float>> m_peaks;
    QImage m_frame;
    mutable QMutex m_mutex;
};

} // namespace of
