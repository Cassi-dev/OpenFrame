import Foundation

/// Trava comum aos testes pesados (transcrição com o whisper e medições de desempenho): rodando
/// juntos, eles disputam GPU e CPU e as medições estouram o limite. Os outros testes continuam em
/// paralelo.
actor HeavyWork {
    static let shared = HeavyWork()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    static func run<T>(_ body: () async throws -> T) async throws -> T {
        await shared.acquire()
        do {
            let result = try await body()
            await shared.release()
            return result
        } catch {
            await shared.release()
            throw error
        }
    }
}

/// Mediana: resiste a quadros soltos atrasados pela máquina ocupada.
func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
