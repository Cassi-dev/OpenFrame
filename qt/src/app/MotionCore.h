#pragma once

#include "Project.h"

#include <QImage>
#include <QList>
#include <QString>
#include <QVariantList>
#include <optional>

// Única ligação da aba Animação com o núcleo: tipos de entrada/saída, loops
// (`LoopKind`/`Segment::animationLoop`, etapa 1 do 04) e quadros das miniaturas
// (`AnimationPreview::frames`, etapa 2).
//
// PROVISÓRIO: sem `CanvasLayout.h` (marca da etapa 1), o loop escolhido fica só
// na memória do app, fora do projeto e do desfazer. Sem `AnimationPreview.h`,
// não há quadros e os cartões mostram o ícone.

#if __has_include("CanvasLayout.h")
#define OF_HAS_MOTION_MODEL 1
#endif
#if __has_include("AnimationPreview.h")
#define OF_HAS_ANIMATION_PREVIEW 1
#endif

namespace of::MotionCore {

/// Animação contínua de um segmento (o `LoopAnimation` do núcleo).
struct Loop {
    QString kind;
    Micros period = 2'000'000;
    double intensity = 0.5;
};

/// Entradas/saídas: [{value, title (nome completo, na dica), short (no cartão), icon}].
QVariantList animationKinds(bool text);
/// Loops: [{value, title, short, icon}].
QVariantList loopKinds();

std::optional<Loop> loop(const Project &p, const QUuid &id);
/// `kind` vazio tira o loop.
void setLoop(Project &p, const QUuid &id, const std::optional<Loop> &loop);

/// Parte animada de uma miniatura: "entry:<tipo>", "exit:<tipo>", "loop:<tipo>" ou "" (repouso).
/// Quadros da miniatura do segmento (texto curto com o estilo dele, ou a imagem da
/// mídia); vazio sem o `AnimationPreview` do núcleo.
QList<QImage> frames(const Segment &seg, const QImage &mediaImage, const QString &part, QSize size, int count);
/// Chave do assunto da miniatura (texto e estilo, ou o material).
QString subjectKey(const Segment &seg);
/// Primeira linha, até ~14 caracteres sem cortar palavras.
QString shortText(const QString &text);

} // namespace of::MotionCore
