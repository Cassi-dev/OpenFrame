#include "Subtitles.h"

#include "TimelineEditor.h"

#include <algorithm>

namespace of::SRT {

namespace {

void sortByStart(QList<SubtitleCue> &cues)
{
    std::stable_sort(cues.begin(), cues.end(), [](const auto &a, const auto &b) { return a.start < b.start; });
}

/// Espaços e tabulações nas pontas (o `.whitespaces` do Swift, sem quebras de linha).
QString trimSpaces(const QString &s)
{
    qsizetype from = 0, to = s.size();
    while (from < to && (s[from] == u' ' || s[from] == u'\t'))
        ++from;
    while (to > from && (s[to - 1] == u' ' || s[to - 1] == u'\t'))
        --to;
    return s.mid(from, to - from);
}

} // namespace

QList<SubtitleCue> parse(const QString &content)
{
    QString normalized = content;
    normalized.replace(QStringLiteral("\r\n"), QStringLiteral("\n")).replace(u'\r', u'\n');
    while (normalized.startsWith(QChar(0xFEFF)))
        normalized.remove(0, 1);
    while (normalized.endsWith(QChar(0xFEFF)))
        normalized.chop(1);

    QList<SubtitleCue> cues;
    for (const QString &block : normalized.split(QStringLiteral("\n\n"))) {
        const QStringList lines = block.split(u'\n');
        const auto timing = std::find_if(lines.cbegin(), lines.cend(),
                                         [](const QString &l) { return l.contains(QStringLiteral("-->")); });
        if (timing == lines.cend())
            continue;
        const QStringList parts = timing->split(QStringLiteral("-->"));
        if (parts.size() != 2)
            continue;
        const auto start = parseTimestamp(parts[0]);
        const auto end = parseTimestamp(parts[1]);
        if (!start || !end || *end <= *start)
            continue;
        const QString text = QStringList(timing + 1, lines.cend()).join(u'\n').trimmed();
        if (text.isEmpty())
            continue;
        cues.append({*start, *end, text});
    }
    sortByStart(cues);
    return cues;
}

std::optional<Micros> parseTimestamp(const QString &raw)
{
    const QStringList tokens = trimSpaces(raw).split(u' ', Qt::SkipEmptyParts);
    QString token = tokens.isEmpty() ? QString() : tokens.first();
    const QStringList pieces = token.replace(u',', u'.').split(u':', Qt::SkipEmptyParts);
    if (pieces.size() != 3)
        return std::nullopt;
    bool okH = false, okM = false, okS = false;
    const double h = pieces[0].toDouble(&okH);
    const double m = pieces[1].toDouble(&okM);
    const double s = pieces[2].toDouble(&okS);
    if (!okH || !okM || !okS)
        return std::nullopt;
    return Time::seconds(h * 3600 + m * 60 + s);
}

QString serialize(const QList<SubtitleCue> &cues)
{
    QStringList blocks;
    for (qsizetype i = 0; i < cues.size(); ++i)
        blocks.append(QStringLiteral("%1\n%2 --> %3\n%4\n")
                          .arg(i + 1)
                          .arg(timestamp(cues[i].start), timestamp(cues[i].end), cues[i].text));
    return blocks.join(u'\n');
}

QString timestamp(Micros t)
{
    const qint64 ms = std::max<qint64>(0, t / 1000);
    return QString::asprintf("%02lld:%02lld:%02lld,%03lld", ms / 3'600'000, (ms / 60'000) % 60, (ms / 1000) % 60,
                             ms % 1000);
}

void importCues(const QList<SubtitleCue> &cues, Project &p, const TextStyle &style)
{
    if (cues.isEmpty())
        return;
    Track track(TrackKind::Text);
    for (const auto &cue : cues)
        track.segments.append(Segment::makeText({cue.text, style}, cue.start,
                                                std::max(TimelineEditor::minDuration, cue.end - cue.start)));
    p.tracks.append(track);
}

QList<SubtitleCue> cues(const Project &p)
{
    QList<SubtitleCue> cues;
    for (const auto &track : p.tracks) {
        if (track.kind != TrackKind::Text || track.hidden)
            continue;
        for (const auto &s : track.segments)
            if (s.text)
                cues.append({s.targetStart, s.targetEnd(), s.text->text});
    }
    sortByStart(cues);
    return cues;
}

} // namespace of::SRT
