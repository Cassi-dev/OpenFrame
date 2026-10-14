import QtQuick

// Degradê curto no topo de uma rolagem sob título fixo: o conteúdo some em vez
// de aparecer cortado colado no título. O primeiro terço fica opaco.
Rectangle {
    property color base: Theme.surface
    height: Theme.scrollFade
    gradient: Gradient {
        GradientStop { position: 0; color: base }
        GradientStop { position: 0.35; color: base }
        GradientStop { position: 1; color: Theme.alpha(base, 0) }
    }
}
