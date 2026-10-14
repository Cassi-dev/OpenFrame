#pragma once

#include "LinearImage.h"
#include "Project.h"

namespace of {

/// Estado de uma animação de entrada/saída num instante.
struct AnimationState {
    double scale = 1;
    double dx = 0;
    double dy = 0;
    double rotation = 0;
    double alpha = 1;
    /// Fração do texto visível (animação "máquina de escrever").
    double reveal = 1;
};

namespace Animations {
AnimationState state(const Segment &seg, Micros local);
/// Desaceleração cúbica (1 - (1 - p)³), com p limitado a 0…1.
double ease(double p);
} // namespace Animations

namespace Transitions {
/// Mistura duas camadas já posicionadas no canvas (do tamanho do canvas).
/// `k` = altura do canvas / 1080.
LinearImage apply(TransitionKind kind, const LinearImage &from, const LinearImage &to, double progress, double k);
} // namespace Transitions

} // namespace of
