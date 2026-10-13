#pragma once

#include <QColor>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

// Itens desenhados com QPainter. Funcionam com o renderizador por software
// (máquinas virtuais sem GPU e o modo de captura offscreen).

namespace of {

/// O símbolo do OpenFrame (Quatro Quadros), com a geometria de
/// `assets/brand/source/build.py` (caixa de 256 × 256). Até 32 px usa o corte
/// pequeno, de folgas mais largas. O quadro de cima é o aceso.
class LogoMark : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QColor frameColor MEMBER m_frameColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor litColor MEMBER m_litColor NOTIFY colorsChanged)

public:
    explicit LogoMark(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

signals:
    void colorsChanged();

private:
    QColor m_frameColor{255, 255, 255, 235};
    QColor m_litColor{0x00, 0xC2, 0xCC};
};

/// Cabeça da agulha do playhead: bloco de topo arredondado que afunila até a
/// espessura da linha, com um brilho suave. O texto do tempo fica por cima, no QML.
class NeedleHead : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QColor color MEMBER m_color NOTIFY changed)
    Q_PROPERTY(qreal taper MEMBER m_taper NOTIFY changed)
    Q_PROPERTY(qreal line MEMBER m_line NOTIFY changed)
    /// Margem para o brilho em volta da forma.
    Q_PROPERTY(qreal glow MEMBER m_glow NOTIFY changed)

public:
    explicit NeedleHead(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

signals:
    void changed();

private:
    QColor m_color{0x00, 0xC2, 0xCC};
    qreal m_taper = 5;
    qreal m_line = 1.5;
    qreal m_glow = 6;
};

/// Retângulo arredondado de contorno tracejado (área de soltar, prévia de onde
/// o material cai na timeline).
class DashedRect : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QColor color MEMBER m_color NOTIFY changed)
    Q_PROPERTY(QColor fill MEMBER m_fill NOTIFY changed)
    Q_PROPERTY(qreal radius MEMBER m_radius NOTIFY changed)
    Q_PROPERTY(qreal lineWidth MEMBER m_lineWidth NOTIFY changed)
    Q_PROPERTY(qreal dash MEMBER m_dash NOTIFY changed)
    Q_PROPERTY(qreal gap MEMBER m_gap NOTIFY changed)

public:
    explicit DashedRect(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

signals:
    void changed();

private:
    QColor m_color{255, 255, 255, 36};
    QColor m_fill{Qt::transparent};
    qreal m_radius = 10;
    qreal m_lineWidth = 1;
    qreal m_dash = 4;
    qreal m_gap = 4;
};

/// Régua da timeline em pílula. Desenha só a parte visível: o item tem a
/// largura da área visível e `offset` é a rolagem horizontal.
class TimelineRuler : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal zoom MEMBER m_zoom NOTIFY changed)
    Q_PROPERTY(qreal offset MEMBER m_offset NOTIFY changed)
    Q_PROPERTY(qreal contentWidth MEMBER m_contentWidth NOTIFY changed)

public:
    explicit TimelineRuler(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    /// Rótulo do tempo `t` (s) com marcas a cada `step` s: "00:05", "00:02.5", "1:00:00".
    static QString label(double t, double step);
    /// Intervalo entre rótulos para o zoom (pontos por segundo): o primeiro com 110 pt ou mais.
    static double majorStep(double zoom);

signals:
    void changed();

private:
    qreal m_zoom = 80;
    qreal m_offset = 0;
    qreal m_contentWidth = 0;
};

/// Forma de onda do trecho `from...to` (segundos de mídia) de um material. Como
/// a régua, desenha só a janela visível de um clipe que pode ser muito largo:
/// `fullWidth` é a largura do clipe e `offset` a posição deste item nele.
class WaveformView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString materialId MEMBER m_materialId NOTIFY changed)
    Q_PROPERTY(qreal from MEMBER m_from NOTIFY changed)
    Q_PROPERTY(qreal to MEMBER m_to NOTIFY changed)
    Q_PROPERTY(QColor color MEMBER m_color NOTIFY changed)
    Q_PROPERTY(qreal fullWidth MEMBER m_fullWidth NOTIFY changed)
    Q_PROPERTY(qreal offset MEMBER m_offset NOTIFY changed)
    Q_PROPERTY(qreal bar MEMBER m_bar NOTIFY changed)
    Q_PROPERTY(qreal gap MEMBER m_gap NOTIFY changed)
    Q_PROPERTY(bool hasPeaks READ hasPeaks NOTIFY peaksChanged)

public:
    explicit WaveformView(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;
    bool hasPeaks() const;

signals:
    void changed();
    void peaksChanged();

private:
    QString m_materialId;
    qreal m_from = 0;
    qreal m_to = 0;
    QColor m_color{255, 255, 255, 82};
    qreal m_fullWidth = 0;
    qreal m_offset = 0;
    qreal m_bar = 2;
    qreal m_gap = 1.5;
};

/// Miniaturas repetidas ao longo do clipe, escolhidas pelo tempo de origem.
/// Mesma janela visível de `WaveformView`; os cantos do clipe são arredondados.
class ThumbnailStrip : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString materialId MEMBER m_materialId NOTIFY changed)
    Q_PROPERTY(bool video MEMBER m_video NOTIFY changed)
    Q_PROPERTY(qreal aspect MEMBER m_aspect NOTIFY changed)
    Q_PROPERTY(qreal sourceStart MEMBER m_sourceStart NOTIFY changed)
    Q_PROPERTY(qreal sourceDuration MEMBER m_sourceDuration NOTIFY changed)
    Q_PROPERTY(qreal materialDuration MEMBER m_materialDuration NOTIFY changed)
    Q_PROPERTY(qreal fullWidth MEMBER m_fullWidth NOTIFY changed)
    Q_PROPERTY(qreal offset MEMBER m_offset NOTIFY changed)
    Q_PROPERTY(qreal radius MEMBER m_radius NOTIFY changed)

public:
    explicit ThumbnailStrip(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

signals:
    void changed();

private:
    QString m_materialId;
    bool m_video = true;
    qreal m_aspect = 16.0 / 9;
    qreal m_sourceStart = 0;
    qreal m_sourceDuration = 0;
    qreal m_materialDuration = 0;
    qreal m_fullWidth = 0;
    qreal m_offset = 0;
    qreal m_radius = 7;
};

/// Primeira miniatura de um material, cortada para preencher (tiles da biblioteca).
class MaterialThumb : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString materialId MEMBER m_materialId NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY imagesChanged)

public:
    explicit MaterialThumb(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;
    bool available() const;

signals:
    void changed();
    void imagesChanged();

private:
    QString m_materialId;
};

/// Quadro do preview, com os cantos arredondados (o AVPlayerLayer do app Swift).
class PreviewFrame : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal radius MEMBER m_radius NOTIFY changed)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY frameChanged)

public:
    explicit PreviewFrame(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;
    bool hasFrame() const;

signals:
    void changed();
    void frameChanged();

private:
    qreal m_radius = 10;
};

} // namespace of
