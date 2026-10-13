#include "FFmpeg.h"

#include <cmath>

namespace of::ff {

InputPtr openInput(const QString &path, QString *error)
{
    AVFormatContext *raw = nullptr;
    int r = avformat_open_input(&raw, path.toUtf8().constData(), nullptr, nullptr);
    if (r < 0) {
        if (error)
            *error = errorString(r);
        return nullptr;
    }
    InputPtr input(raw);
    r = avformat_find_stream_info(input.get(), nullptr);
    if (r < 0) {
        if (error)
            *error = errorString(r);
        return nullptr;
    }
    return input;
}

CodecPtr openDecoder(const AVStream *stream, QString *error)
{
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        if (error)
            *error = QStringLiteral("sem decodificador para %1").arg(QString::fromUtf8(avcodec_get_name(stream->codecpar->codec_id)));
        return nullptr;
    }
    CodecPtr ctx(avcodec_alloc_context3(codec));
    int r = avcodec_parameters_to_context(ctx.get(), stream->codecpar);
    if (r >= 0) {
        ctx->pkt_timebase = stream->time_base;
        ctx->thread_count = 0;
        r = avcodec_open2(ctx.get(), codec, nullptr);
    }
    if (r < 0) {
        if (error)
            *error = errorString(r);
        return nullptr;
    }
    return ctx;
}

DisplayTransform displayTransform(const AVStream *stream)
{
    const AVPacketSideData *sd = av_packet_side_data_get(stream->codecpar->coded_side_data,
                                                         stream->codecpar->nb_coded_side_data,
                                                         AV_PKT_DATA_DISPLAYMATRIX);
    if (!sd || sd->size < int(9 * sizeof(int32_t)))
        return {};
    const auto *matrix = reinterpret_cast<const int32_t *>(sd->data);
    // Mesma conta do autorotate do ffmpeg: o ângulo da matriz é anti-horário.
    double theta = -av_display_rotation_get(matrix);
    if (std::isnan(theta))
        return {};
    theta -= 360 * std::floor(theta / 360 + 0.9 / 360);
    DisplayTransform t;
    t.rotation = (int(std::lround(theta / 90)) % 4) * 90;
    const double det = double(matrix[0]) * matrix[4] - double(matrix[1]) * matrix[3];
    t.mirrored = det < 0;
    return t;
}

bool isRealVideo(const AVStream *stream)
{
    return stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO && !(stream->disposition & AV_DISPOSITION_ATTACHED_PIC);
}

} // namespace of::ff
