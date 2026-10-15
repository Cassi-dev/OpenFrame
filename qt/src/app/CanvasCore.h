#pragma once

#include "Project.h"

#include <QList>
#include <QPointF>
#include <QSizeF>
#include <QUuid>
#include <array>
#include <optional>

// Única ligação do overlay do preview com a geometria do núcleo (`CanvasLayout`,
// `Snapping` e as edições do `TimelineEditor`, etapa 1 do 04). O resto do app só
// chama `of::CanvasCore`.
//
// PROVISÓRIO: sem `CanvasLayout.h` no núcleo, as caixas são falsas (tamanho fixo,
// sem medir o texto) e não há ímã nem guias. Com o cabeçalho, tudo vem do núcleo.

#if __has_include("CanvasLayout.h")
#include "CanvasLayout.h"
#include "Snapping.h"
#define OF_HAS_CANVAS_LAYOUT 1
#else
namespace of {
// Só os tipos (os do núcleo têm estes nomes e campos).
struct ElementBox {
    QUuid id;
    bool isText = false;
    QPointF center;
    QSizeF size;
    double scale = 1;
    double rotation = 0;
};
struct SnapGuide {
    enum class Axis { Vertical, Horizontal };
    enum class Kind { CanvasCenter, CanvasEdge, SafeMargin, Element };
    Axis axis = Axis::Vertical;
    double position = 0;
    Kind kind = Kind::Element;
    bool operator==(const SnapGuide &) const = default;
};
} // namespace of
#endif

namespace of::CanvasCore {

/// Faixa de `TextStyle::maxWidth` aceita pelas alças laterais.
inline constexpr double minTextWidth = 0.1;
inline constexpr double maxTextWidth = 3;

/// Elementos visíveis no instante, na ordem de desenho (o primeiro fica embaixo).
QList<ElementBox> boxes(const Project &project, Micros time);
/// Cantos normalizados da caixa girada: superior esquerdo, superior direito,
/// inferior direito, inferior esquerdo.
std::array<QPointF, 4> corners(const ElementBox &box, double aspect);
/// Id do elemento mais acima sob o ponto (normalizado).
std::optional<QUuid> hitTest(QPointF point, const QList<ElementBox> &boxes, double aspect);

struct SnappedMove {
    QPointF center;
    QList<SnapGuide> guides;
};
SnappedMove snapMove(const ElementBox &box, QPointF proposed, const QList<ElementBox> &others, double aspect,
                     QSizeF threshold);
double snapRotation(double degrees);

/// Posição (centro normalizado), escala e rotação de um clipe ou texto.
void setPlacement(Project &p, const QUuid &id, QPointF center, double scale, double rotation);
/// Largura de quebra do texto (fração da largura do canvas).
void setTextWidth(Project &p, const QUuid &id, double maxWidth);
/// O texto está numa faixa de legendas automáticas (a largura vale para todas).
bool isInAutoCaptions(const Project &p, const QUuid &id);

} // namespace of::CanvasCore
