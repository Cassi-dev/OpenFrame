#include "Waveform.h"

#include "FFmpeg.h"

#include <algorithm>
#include <cmath>

namespace of::Waveform {

QList<float> peaks(const QString &path, double perSecond, QString *error)
{
    const ff::InputPtr input = ff::openInput(path, error);
    if (!input)
        return {};
    const int index = av_find_best_stream(input.get(), AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (index < 0)
        return {};
    const AVStream *stream = input->streams[index];
    for (unsigned i = 0; i < input->nb_streams; ++i)
        if (int(i) != index)
            input->streams[i]->discard = AVDISCARD_ALL;
    const ff::CodecPtr codec = ff::openDecoder(stream, error);
    if (!codec)
        return {};

    constexpr int sampleRate = 8000;
    SwrContext *rawSwr = nullptr;
    const AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
    if (swr_alloc_set_opts2(&rawSwr, &mono, AV_SAMPLE_FMT_FLT, sampleRate, &codec->ch_layout, codec->sample_fmt,
                            codec->sample_rate, 0, nullptr) < 0)
        return {};
    const ff::SwrPtr swr(rawSwr);
    if (swr_init(swr.get()) < 0)
        return {};

    const int bucket = std::max(1, int(sampleRate / perSecond));
    QList<float> peaks;
    float current = 0;
    int filled = 0;
    std::vector<float> samples;
    const auto consume = [&](const uint8_t **data, int count) {
        const int capacity = swr_get_out_samples(swr.get(), count);
        samples.resize(size_t(std::max(capacity, 0)));
        uint8_t *out = reinterpret_cast<uint8_t *>(samples.data());
        const int got = swr_convert(swr.get(), &out, capacity, data, count);
        for (int i = 0; i < got; ++i) {
            current = std::max(current, std::abs(samples[size_t(i)]));
            if (++filled == bucket) {
                peaks.append(current);
                current = 0;
                filled = 0;
            }
        }
    };

    const ff::PacketPtr packet = ff::makePacket();
    const ff::FramePtr frame = ff::makeFrame();
    const auto drain = [&] {
        while (avcodec_receive_frame(codec.get(), frame.get()) == 0) {
            consume(const_cast<const uint8_t **>(frame->extended_data), frame->nb_samples);
            av_frame_unref(frame.get());
        }
    };
    while (av_read_frame(input.get(), packet.get()) >= 0) {
        if (packet->stream_index == index && avcodec_send_packet(codec.get(), packet.get()) >= 0)
            drain();
        av_packet_unref(packet.get());
    }
    avcodec_send_packet(codec.get(), nullptr);
    drain();
    consume(nullptr, 0); // o que sobrou no reamostrador

    if (filled > 0)
        peaks.append(current);
    const float top = peaks.isEmpty() ? 0 : *std::max_element(peaks.cbegin(), peaks.cend());
    if (top > 0)
        for (float &p : peaks)
            p /= top;
    return peaks;
}

} // namespace of::Waveform
