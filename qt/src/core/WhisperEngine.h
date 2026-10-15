#pragma once

#include "WhisperModels.h"
#include "WordAligner.h"

#include <atomic>
#include <functional>
#include <optional>
#include <vector>

namespace of {

/// Ponte para o whisper.cpp na CPU (interno: o app usa o `Transcriber`). Um contexto (modelo) fica carregado
/// entre as transcrições e é liberado depois de 3 min parado; as transcrições são uma de cada vez. Mesmos
/// parâmetros do `WhisperEngine.swift`.
///
/// Com as variantes de CPU (`OPENFRAME_GGML_DL`), o backend é carregado na primeira transcrição (nunca ao abrir
/// o app), da primeira pasta que tiver um: a pasta do executável, `../lib/openframe` a partir dela (AppImage) e a
/// pasta do build; `OPENFRAME_GGML_DIR`, quando definida, é a única procurada. O ggml escolhe a variante de maior
/// nota que a CPU suporta.
namespace WhisperEngine {

/// Como os tempos das palavras são calculados.
enum class Timing {
    /// `token_timestamps`: t0/t1 de cada token pelas probabilidades dos tokens de tempo.
    Tokens,
    /// DTW sobre as cabeças de alinhamento do modelo: o início de cada token.
    Dtw
};

struct Options {
    /// Vazio = detectar.
    QString language;
    Timing timing = Timing::Dtw;
    /// Ajusta as fronteiras pela energia do áudio (`WordAligner`).
    bool refine = true;
    /// Entre 1 e 8: os núcleos menos 2.
    int threads = defaultThreads();
    static int defaultThreads();
};

/// O whisper foi compilado e há um backend de CPU (carrega das pastas padrão na primeira chamada).
bool isAvailable();
/// Carrega o backend de CPU só de `directory` (testes). Verdadeiro se, depois disso, há um backend de CPU.
/// Sem efeito se um já estiver carregado.
bool loadBackends(const QString &directory);
/// Backend de CPU carregado, a descrição da CPU e os recursos que a variante usa; vazio sem backend.
QString backendDescription();

/// Transcreve áudio mono de 16 kHz. Bloqueia a thread. Vazio com `cancelled` (sem erro) ou com `error`.
std::optional<QList<EngineWord>> transcribe(const std::vector<float> &samples, const QString &modelPath,
                                            std::optional<WhisperModel> model, const Options &options,
                                            const std::atomic<bool> &cancelled,
                                            const std::function<void(double)> &progress, QString *error);

/// Libera o modelo carregado (ex.: antes de apagá-lo).
void unload();

/// Junta tokens em palavras: um token que começa com espaço abre uma palavra nova; os outros (sub-palavras,
/// pontuação grudada) continuam a anterior. Os bytes são juntados antes de virar texto (um caractere acentuado
/// pode vir partido em dois tokens). Exposto para os testes.
struct Token {
    QByteArray bytes;
    double start = 0;
    double end = 0;
    double probability = 0;
};
QList<EngineWord> joinTokens(const QList<QList<Token>> &segments);
} // namespace WhisperEngine

} // namespace of
