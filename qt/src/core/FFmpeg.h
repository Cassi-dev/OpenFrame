#pragma once

// Uso interno do núcleo: cabeçalhos do FFmpeg e donos RAII dos seus objetos.
// Só APIs presentes do FFmpeg 6.1 ao 9 (ch_layout, send/receive, coded_side_data).

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
}

#include <QString>
#include <memory>

namespace of::ff {

struct FormatInputDeleter {
    void operator()(AVFormatContext *c) const { avformat_close_input(&c); }
};
struct CodecDeleter {
    void operator()(AVCodecContext *c) const { avcodec_free_context(&c); }
};
struct FrameDeleter {
    void operator()(AVFrame *f) const { av_frame_free(&f); }
};
struct PacketDeleter {
    void operator()(AVPacket *p) const { av_packet_free(&p); }
};
struct SwsDeleter {
    void operator()(SwsContext *c) const { sws_freeContext(c); }
};
struct SwrDeleter {
    void operator()(SwrContext *c) const { swr_free(&c); }
};

using InputPtr = std::unique_ptr<AVFormatContext, FormatInputDeleter>;
using CodecPtr = std::unique_ptr<AVCodecContext, CodecDeleter>;
using FramePtr = std::unique_ptr<AVFrame, FrameDeleter>;
using PacketPtr = std::unique_ptr<AVPacket, PacketDeleter>;
using SwsPtr = std::unique_ptr<SwsContext, SwsDeleter>;
using SwrPtr = std::unique_ptr<SwrContext, SwrDeleter>;

inline FramePtr makeFrame() { return FramePtr(av_frame_alloc()); }
inline PacketPtr makePacket() { return PacketPtr(av_packet_alloc()); }

inline QString errorString(int code)
{
    char buf[AV_ERROR_MAX_STRING_SIZE] = {};
    av_strerror(code, buf, sizeof buf);
    return QString::fromUtf8(buf);
}

/// Abre o arquivo e lê as informações das trilhas.
InputPtr openInput(const QString &path, QString *error = nullptr);

/// Abre o decodificador da trilha (com threads automáticas).
CodecPtr openDecoder(const AVStream *stream, QString *error = nullptr);

/// Rotação de exibição da trilha em graus no sentido horário (0, 90, 180, 270)
/// e se a imagem é espelhada, a partir da matriz de exibição (como o
/// `preferredTransform` do AVFoundation e o autorotate do ffmpeg).
struct DisplayTransform {
    int rotation = 0;
    bool mirrored = false;
};
DisplayTransform displayTransform(const AVStream *stream);

/// Trilha de vídeo de verdade (ignora capas de álbum e miniaturas anexadas).
bool isRealVideo(const AVStream *stream);

/// Converte entre a base de tempo da trilha e microssegundos.
inline qint64 toMicros(int64_t ts, AVRational tb) { return av_rescale_q(ts, tb, AVRational{1, 1'000'000}); }
inline int64_t fromMicros(qint64 us, AVRational tb) { return av_rescale_q(us, AVRational{1, 1'000'000}, tb); }

} // namespace of::ff
