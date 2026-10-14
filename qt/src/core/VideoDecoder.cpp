#include "VideoDecoder.h"

#include "FFmpeg.h"
#include "ToneMap.h"

#include <QTransform>
#include <cmath>

namespace of {

namespace {

/// Avançar decodificando é mais barato que buscar até esta distância.
constexpr Micros forwardLimit = 3 * Time::second;

/// Matriz YUV → RGB do swscale para a marca do arquivo. Sem marca: BT.709 em
/// HD e BT.601 em SD, como os players fazem (o padrão do swscale é sempre 601).
int swsColorspace(AVColorSpace space, int width, int height)
{
    switch (space) {
    case AVCOL_SPC_BT709: return SWS_CS_ITU709;
    case AVCOL_SPC_BT470BG:
    case AVCOL_SPC_SMPTE170M: return SWS_CS_ITU601;
    case AVCOL_SPC_SMPTE240M: return SWS_CS_SMPTE240M;
    case AVCOL_SPC_FCC: return SWS_CS_FCC;
    case AVCOL_SPC_BT2020_NCL:
    case AVCOL_SPC_BT2020_CL: return SWS_CS_BT2020;
    default: return width >= 1280 || height > 576 ? SWS_CS_ITU709 : SWS_CS_ITU601;
    }
}

bool isFullRange(const AVFrame *f)
{
    switch (f->format) {
    case AV_PIX_FMT_YUVJ420P:
    case AV_PIX_FMT_YUVJ422P:
    case AV_PIX_FMT_YUVJ444P:
    case AV_PIX_FMT_YUVJ440P:
    case AV_PIX_FMT_YUVJ411P: return true;
    default: return f->color_range == AVCOL_RANGE_JPEG;
    }
}

bool hasAlpha(int format)
{
    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(AVPixelFormat(format));
    return desc && (desc->flags & AV_PIX_FMT_FLAG_ALPHA);
}

/// Curva HDR do quadro (ou da trilha, se o quadro não disser).
ToneMap::Transfer transferOf(const AVFrame *f, const AVStream *stream)
{
    const AVColorTransferCharacteristic trc =
        f->color_trc != AVCOL_TRC_UNSPECIFIED ? f->color_trc : stream->codecpar->color_trc;
    switch (trc) {
    case AVCOL_TRC_ARIB_STD_B67: return ToneMap::Transfer::Hlg;
    case AVCOL_TRC_SMPTE2084: return ToneMap::Transfer::Pq;
    default: return ToneMap::Transfer::Sdr;
    }
}

bool isRgb(int format)
{
    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(AVPixelFormat(format));
    return desc && (desc->flags & AV_PIX_FMT_FLAG_RGB);
}

} // namespace

struct VideoDecoder::Impl {
    ff::InputPtr input;
    ff::CodecPtr codec;
    AVStream *stream = nullptr;
    ff::PacketPtr packet = ff::makePacket();
    ff::DisplayTransform transform;
    double sar = 1;
    Micros streamStart = 0;
    Micros duration = 0;

    // Quadro atual (o último devolvido) e o seguinte, já decodificado.
    ff::FramePtr current;
    Micros currentTime = 0;
    ff::FramePtr next;
    Micros nextTime = 0;
    bool eof = false;
    bool drained = false;
    int seeks = 0;

    // Conversão para RGB, guardada enquanto formato e tamanhos não mudam.
    ff::SwsPtr sws;
    int swsFormat = -1, swsW = 0, swsH = 0, swsOutW = 0, swsOutH = 0;
    AVColorSpace swsSpace = AVCOL_SPC_UNSPECIFIED;
    bool swsFull = false;
    bool swsHdr = false;
    QImage image;
    QSize imageMaxSize;

    Micros frameTime(const AVFrame *f) const
    {
        const int64_t ts = f->best_effort_timestamp != AV_NOPTS_VALUE ? f->best_effort_timestamp : f->pts;
        if (ts == AV_NOPTS_VALUE)
            return 0;
        return ff::toMicros(ts, stream->time_base) - streamStart;
    }

    /// Próximo quadro decodificado, ou nulo no fim do arquivo.
    ff::FramePtr decodeOne()
    {
        ff::FramePtr frame = ff::makeFrame();
        for (;;) {
            const int r = avcodec_receive_frame(codec.get(), frame.get());
            if (r == 0)
                return frame;
            if (r == AVERROR_EOF || (r != AVERROR(EAGAIN)))
                return nullptr;
            if (drained)
                return nullptr;
            // Precisa de mais pacotes.
            for (;;) {
                const int rr = av_read_frame(input.get(), packet.get());
                if (rr < 0) {
                    avcodec_send_packet(codec.get(), nullptr);
                    drained = true;
                    break;
                }
                if (packet->stream_index == stream->index) {
                    avcodec_send_packet(codec.get(), packet.get());
                    av_packet_unref(packet.get());
                    break;
                }
                av_packet_unref(packet.get());
            }
        }
    }

    void seek(Micros t)
    {
        ++seeks;
        av_seek_frame(input.get(), stream->index, ff::fromMicros(std::max<Micros>(0, t) + streamStart, stream->time_base),
                      AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(codec.get());
        current.reset();
        next.reset();
        eof = drained = false;
        image = {};
    }

    bool advanceTo(Micros t)
    {
        for (;;) {
            if (!next) {
                next = decodeOne();
                if (!next) {
                    eof = true;
                    return bool(current);
                }
                nextTime = frameTime(next.get());
            }
            if (!current || nextTime <= t) {
                current = std::move(next);
                currentTime = nextTime;
                image = {};
                continue;
            }
            return true;
        }
    }

    QSize outputSize(QSize maxSize) const
    {
        const double w = std::max(1.0, std::round(codec->width * sar));
        const double h = std::max(1, codec->height);
        if (!maxSize.isValid() || maxSize.isEmpty())
            return {int(w), int(h)};
        // `maxSize` vale para a imagem já girada.
        const bool turned = transform.rotation % 180 != 0;
        const double maxW = turned ? maxSize.height() : maxSize.width();
        const double maxH = turned ? maxSize.width() : maxSize.height();
        const double scale = std::min({1.0, maxW / w, maxH / h});
        return {std::max(1, int(std::lround(w * scale))), std::max(1, int(std::lround(h * scale)))};
    }

    QImage convert(const AVFrame *f, QSize maxSize)
    {
        const QSize out = outputSize(maxSize);
        const bool full = isFullRange(f);
        // HDR sai em 16 bits por canal (ainda em BT.2020) e passa pelo ToneMap.
        const ToneMap::Transfer transfer = transferOf(f, stream);
        const bool hdr = transfer != ToneMap::Transfer::Sdr;
        if (!sws || swsFormat != f->format || swsW != f->width || swsH != f->height || swsOutW != out.width() ||
            swsOutH != out.height() || swsSpace != f->colorspace || swsFull != full || swsHdr != hdr) {
            sws.reset(sws_getContext(f->width, f->height, AVPixelFormat(f->format), out.width(), out.height(),
                                     hdr ? AV_PIX_FMT_RGBA64 : AV_PIX_FMT_BGRA,
                                     SWS_BICUBIC | SWS_ACCURATE_RND | SWS_FULL_CHR_H_INT | SWS_FULL_CHR_H_INP,
                                     nullptr, nullptr, nullptr));
            if (!sws)
                return {};
            if (!isRgb(f->format)) {
                const int *coefficients = sws_getCoefficients(swsColorspace(f->colorspace, f->width, f->height));
                sws_setColorspaceDetails(sws.get(), coefficients, full ? 1 : 0, sws_getCoefficients(SWS_CS_DEFAULT),
                                         1, 0, 1 << 16, 1 << 16);
            }
            swsFormat = f->format;
            swsW = f->width;
            swsH = f->height;
            swsOutW = out.width();
            swsOutH = out.height();
            swsSpace = f->colorspace;
            swsFull = full;
            swsHdr = hdr;
        }
        if (hdr) {
            QImage wide(out, QImage::Format_RGBA64);
            uint8_t *dst[4] = {wide.bits(), nullptr, nullptr, nullptr};
            const int dstStride[4] = {int(wide.bytesPerLine()), 0, 0, 0};
            sws_scale(sws.get(), f->data, f->linesize, 0, f->height, dst, dstStride);
            return oriented(ToneMap::toSdr(wide, transfer));
        }
        // BGRA na memória = ARGB32 no Qt (little-endian, como todas as plataformas-alvo).
        QImage img(out, QImage::Format_ARGB32);
        uint8_t *dst[4] = {img.bits(), nullptr, nullptr, nullptr};
        const int dstStride[4] = {int(img.bytesPerLine()), 0, 0, 0};
        sws_scale(sws.get(), f->data, f->linesize, 0, f->height, dst, dstStride);
        // Quadro opaco: ARGB32 e pré-multiplicado são os mesmos bytes.
        if (hasAlpha(f->format))
            img.convertTo(QImage::Format_ARGB32_Premultiplied);
        else
            img.reinterpretAsFormat(QImage::Format_ARGB32_Premultiplied);
        return oriented(std::move(img));
    }

    /// Aplica a rotação/espelhamento da trilha.
    QImage oriented(QImage img) const
    {
        if (transform.rotation != 0 || transform.mirrored) {
            QTransform m;
            if (transform.mirrored)
                m.scale(-1, 1);
            m.rotate(transform.rotation);
            img = img.transformed(m);
        }
        return img;
    }
};

VideoDecoder::VideoDecoder() : d(std::make_unique<Impl>()) {}
VideoDecoder::~VideoDecoder() = default;

std::unique_ptr<VideoDecoder> VideoDecoder::open(const QString &path, QString *error)
{
    std::unique_ptr<VideoDecoder> decoder(new VideoDecoder);
    Impl &d = *decoder->d;
    d.input = ff::openInput(path, error);
    if (!d.input)
        return nullptr;
    for (unsigned i = 0; i < d.input->nb_streams; ++i)
        if (ff::isRealVideo(d.input->streams[i])) {
            d.stream = d.input->streams[i];
            break;
        }
    if (!d.stream) {
        if (error)
            *error = QStringLiteral("o arquivo não tem vídeo");
        return nullptr;
    }
    // As outras trilhas não precisam nem ser lidas pelo demuxer.
    for (unsigned i = 0; i < d.input->nb_streams; ++i)
        if (d.input->streams[i] != d.stream)
            d.input->streams[i]->discard = AVDISCARD_ALL;
    d.codec = ff::openDecoder(d.stream, error);
    if (!d.codec)
        return nullptr;
    d.transform = ff::displayTransform(d.stream);
    const AVRational sar = av_guess_sample_aspect_ratio(d.input.get(), d.stream, nullptr);
    if (sar.num > 0 && sar.den > 0)
        d.sar = av_q2d(sar);
    if (d.stream->start_time != AV_NOPTS_VALUE)
        d.streamStart = ff::toMicros(d.stream->start_time, d.stream->time_base);
    if (d.stream->duration != AV_NOPTS_VALUE)
        d.duration = ff::toMicros(d.stream->duration, d.stream->time_base);
    else if (d.input->duration != AV_NOPTS_VALUE)
        d.duration = d.input->duration;
    return decoder;
}

QImage VideoDecoder::frameAt(Micros t, QSize maxSize)
{
    Impl &impl = *d;
    const bool inCurrent = impl.current && impl.currentTime <= t && (impl.next ? t < impl.nextTime : impl.eof);
    if (!inCurrent) {
        if (!impl.current || t < impl.currentTime || t - impl.currentTime > forwardLimit)
            impl.seek(t);
        if (!impl.advanceTo(t))
            return {};
    }
    if (impl.image.isNull() || impl.imageMaxSize != maxSize) {
        impl.image = impl.convert(impl.current.get(), maxSize);
        impl.imageMaxSize = maxSize;
    }
    return impl.image;
}

QSize VideoDecoder::displaySize() const
{
    const QSize s = d->outputSize({});
    return d->transform.rotation % 180 != 0 ? s.transposed() : s;
}

Micros VideoDecoder::duration() const { return d->duration; }
Micros VideoDecoder::lastFrameTime() const { return d->currentTime; }
int VideoDecoder::seekCount() const { return d->seeks; }

// MARK: - DecoderCache

QImage DecoderCache::frame(const QUuid &segment, const QString &path, Micros t, QSize maxSize)
{
    std::shared_ptr<Entry> entry;
    {
        QMutexLocker locker(&m_lock);
        auto it = std::find_if(m_entries.begin(), m_entries.end(), [&](const auto &e) { return e.first == segment; });
        if (it != m_entries.end() && it->second->path == path) {
            m_entries.splice(m_entries.begin(), m_entries, it);
        } else {
            if (it != m_entries.end())
                m_entries.erase(it);
            m_entries.emplace_front(segment, std::make_shared<Entry>());
            m_entries.front().second->path = path;
            while (int(m_entries.size()) > m_capacity)
                m_entries.pop_back();
        }
        entry = m_entries.front().second;
    }
    QMutexLocker locker(entry->lock.get());
    if (!entry->decoder && !entry->failed) {
        entry->decoder = VideoDecoder::open(path);
        entry->failed = !entry->decoder;
    }
    return entry->decoder ? entry->decoder->frameAt(t, maxSize) : QImage();
}

void DecoderCache::clear()
{
    QMutexLocker locker(&m_lock);
    m_entries.clear();
}

} // namespace of
