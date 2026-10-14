#pragma once

// Modelos dos filtros "fotográficos" (Mono, Noir, Cromo…): a versão Swift usa os
// CIPhotoEffect* do Core Image, que não têm fórmula pública. Cada modelo é uma
// reconstrução ajustada às cores medidas do Swift (qt/tests/tools/efeitos):
// polinômio de grau ≤ 2 nas cores de entrada seguido de uma curva por canal
// (17 pontos, saída em sRGB). Não é uma tabela amostrada do filtro.

namespace of::filtermodels {

struct Model {
    /// Entrada em luz linear (senão, em sRGB).
    bool linearInput;
    /// 1: r, g, b, 1; 2: também r², g², b², rg, rb, gb.
    int order;
    float m[3][10];
    float curve[3][17];
};

extern const Model mono, noir, tonal, chrome, fade, instant, process, transfer, sepia;

} // namespace of::filtermodels
