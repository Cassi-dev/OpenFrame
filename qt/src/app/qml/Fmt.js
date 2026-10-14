.pragma library

// Formatos dos valores mostrados nos sliders (os mesmos do inspetor Swift).

function percent(v) { return Math.round(v * 100) + "%" }
function signedPercent(v) { const n = Math.round(v * 100); return (n >= 0 ? "+" : "") + n }
function degrees(v) { return Math.round(v) + "°" }
function seconds(v) { return v.toFixed(1) + "s" }
function speed(v) { return v.toFixed(2) + "x" }
/// Medidas em em mostradas como % do tamanho da fonte.
function em(v) { return String(Math.round(v * 100)) }
function signedEm(v) { const n = Math.round(v * 100); return n === 0 ? "0" : (n > 0 ? "+" : "") + n }
function fontSize(v) { return String(Math.round(v * 1000)) }
function oneDecimal(v) { return v.toFixed(1) }

/// Valor no objeto pelo caminho "a.b.c" (ou `fallback` se faltar).
function at(obj, path, fallback) {
    let o = obj
    const keys = path.split(".")
    for (let i = 0; i < keys.length; ++i) {
        if (o === undefined || o === null) return fallback
        o = o[keys[i]]
    }
    return o === undefined || o === null ? fallback : o
}

function color(c, fallback) {
    if (!c) return fallback
    return Qt.rgba(c.r, c.g, c.b, c.a)
}
