// Gerado por scripts/vendorizar-whisper.sh: escolhe a implementação da arquitetura compilada.
#if defined(__aarch64__)
#include "arch/arm/repack.cpp"
#elif defined(__x86_64__)
#include "arch/x86/repack.cpp"
#endif
