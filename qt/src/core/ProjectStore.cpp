#include "ProjectStore.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>

namespace of::ProjectStore {

QString uuidString(const QUuid &id) { return id.toString(QUuid::WithoutBraces).toUpper(); }

// MARK: - Gravação

namespace {

QJsonObject json(const TimeRange &r) { return {{"start", r.start}, {"duration", r.duration}}; }

QJsonObject json(const RGBA &c) { return {{"r", c.r}, {"g", c.g}, {"b", c.b}, {"a", c.a}}; }

QJsonObject json(const Transform &t)
{
    return {{"scale", t.scale}, {"x", t.x}, {"y", t.y}, {"rotation", t.rotation}};
}

QJsonObject json(const Adjust &a)
{
    return {{"brightness", a.brightness}, {"contrast", a.contrast}, {"saturation", a.saturation},
            {"exposure", a.exposure},     {"temperature", a.temperature}, {"tint", a.tint},
            {"highlights", a.highlights}, {"shadows", a.shadows},   {"hue", a.hue},
            {"sharpen", a.sharpen},       {"vignette", a.vignette}, {"fade", a.fade},
            {"grain", a.grain}};
}

QJsonObject json(const FilterSetting &f) { return {{"preset", enumKey(f.preset)}, {"intensity", f.intensity}}; }

QJsonObject json(const VideoEffect &e)
{
    return {{"id", uuidString(e.id)}, {"kind", enumKey(e.kind)}, {"intensity", e.intensity}};
}

QJsonObject json(const SegmentAnimation &a) { return {{"kind", enumKey(a.kind)}, {"duration", a.duration}}; }

QJsonObject json(const Transition &t) { return {{"kind", enumKey(t.kind)}, {"duration", t.duration}}; }

QJsonObject json(const TextStyle &s)
{
    return {{"fontName", s.fontName},
            {"fontFace", s.fontFace},
            {"fontSize", s.fontSize},
            {"bold", s.bold},
            {"italic", s.italic},
            {"underline", s.underline},
            {"textCase", enumKey(s.textCase)},
            {"color", json(s.color)},
            {"opacity", s.opacity},
            {"strokeColor", json(s.strokeColor)},
            {"strokeWidth", s.strokeWidth},
            {"letterSpacing", s.letterSpacing},
            {"lineSpacing", s.lineSpacing},
            {"backgroundEnabled", s.backgroundEnabled},
            {"backgroundColor", json(s.backgroundColor)},
            {"backgroundRadius", s.backgroundRadius},
            {"backgroundPaddingX", s.backgroundPaddingX},
            {"backgroundPaddingY", s.backgroundPaddingY},
            {"shadow", s.shadow},
            {"shadowColor", json(s.shadowColor)},
            {"shadowDistance", s.shadowDistance},
            {"shadowAngle", s.shadowAngle},
            {"shadowBlur", s.shadowBlur},
            {"alignment", enumKey(s.alignment)},
            {"x", s.x},
            {"y", s.y},
            {"scale", s.scale},
            {"rotation", s.rotation},
            {"maxWidth", s.maxWidth}};
}

QJsonObject json(const Segment &s)
{
    QJsonArray effects;
    for (const auto &e : s.effects)
        effects.append(json(e));
    QJsonObject o{{"id", uuidString(s.id)},
                  {"source", json(s.source)},
                  {"targetStart", s.targetStart},
                  {"speed", s.speed},
                  {"volume", s.volume},
                  {"fadeIn", s.fadeIn},
                  {"fadeOut", s.fadeOut},
                  {"transform", json(s.transform)},
                  {"opacity", s.opacity},
                  {"adjust", json(s.adjust)},
                  {"effects", effects}};
    if (s.materialId)
        o["materialId"] = uuidString(*s.materialId);
    if (s.filter)
        o["filter"] = json(*s.filter);
    if (s.animationIn)
        o["animationIn"] = json(*s.animationIn);
    if (s.animationOut)
        o["animationOut"] = json(*s.animationOut);
    if (s.transition)
        o["transition"] = json(*s.transition);
    if (s.text)
        o["text"] = QJsonObject{{"text", s.text->text}, {"style", json(s.text->style)}};
    return o;
}

QJsonObject json(const Track &t)
{
    QJsonArray segments;
    for (const auto &s : t.segments)
        segments.append(json(s));
    return {{"id", uuidString(t.id)}, {"kind", enumKey(t.kind)}, {"isMain", t.isMain},
            {"muted", t.muted},       {"hidden", t.hidden},      {"segments", segments}};
}

QJsonObject json(const Material &m)
{
    return {{"id", uuidString(m.id)}, {"kind", enumKey(m.kind)}, {"path", m.path},
            {"name", m.name},         {"duration", m.duration},  {"width", m.width},
            {"height", m.height},     {"hasAudio", m.hasAudio}};
}

/// Enum com valor associado, como o `Codable` sintetizado do Swift grava:
/// `{"black":{}}`, `{"color":{"_0":{…}}}`, `{"blur":{"_0":0.6}}`.
QJsonObject json(const CanvasBackground &b)
{
    if (const RGBA *c = b.colorValue())
        return {{"color", QJsonObject{{"_0", json(*c)}}}};
    if (const auto blur = b.blurIntensity())
        return {{"blur", QJsonObject{{"_0", *blur}}}};
    return {{"black", QJsonObject{}}};
}

} // namespace

QJsonObject toJson(const Project &p)
{
    QJsonArray materials;
    for (const auto &m : p.materials)
        materials.append(json(m));
    QJsonArray tracks;
    for (const auto &t : p.tracks)
        tracks.append(json(t));
    return {{"formatVersion", p.formatVersion},
            {"name", p.name},
            {"canvas", QJsonObject{{"aspect", enumKey(p.canvas.aspect)}, {"background", json(p.canvas.background)}}},
            {"fps", p.fps},
            {"materials", materials},
            {"tracks", tracks}};
}

QByteArray encode(const Project &p) { return QJsonDocument(toJson(p)).toJson(QJsonDocument::Indented); }

// MARK: - Leitura

namespace {

/// Leitor que guarda o primeiro erro com o caminho da chave ("tracks[0].segments[1].speed").
class Reader
{
public:
    QString error;

    bool failed() const { return !error.isEmpty(); }

    void fail(const QString &path, const QString &what)
    {
        if (error.isEmpty())
            error = QStringLiteral("%1: %2").arg(path, what);
    }

    QJsonValue required(const QJsonObject &o, const QString &path, const char *key)
    {
        const auto it = o.constFind(QLatin1StringView(key));
        if (it == o.constEnd() || it->isNull() || it->isUndefined()) {
            fail(path + u'.' + QLatin1StringView(key), QStringLiteral("campo obrigatório ausente"));
            return {};
        }
        return *it;
    }

    static bool present(const QJsonObject &o, const char *key)
    {
        const auto it = o.constFind(QLatin1StringView(key));
        return it != o.constEnd() && !it->isNull() && !it->isUndefined();
    }

    QJsonObject object(const QJsonValue &v, const QString &path)
    {
        if (!v.isObject())
            fail(path, QStringLiteral("objeto esperado"));
        return v.toObject();
    }

    QJsonArray array(const QJsonValue &v, const QString &path)
    {
        if (!v.isArray())
            fail(path, QStringLiteral("lista esperada"));
        return v.toArray();
    }

    double number(const QJsonValue &v, const QString &path)
    {
        if (!v.isDouble())
            fail(path, QStringLiteral("número esperado"));
        return v.toDouble();
    }

    qint64 integer(const QJsonValue &v, const QString &path)
    {
        const double d = v.toDouble();
        if (!v.isDouble() || d != std::trunc(d)) {
            fail(path, QStringLiteral("inteiro esperado"));
            return 0;
        }
        return v.toInteger(qint64(d));
    }

    bool boolean(const QJsonValue &v, const QString &path)
    {
        if (!v.isBool())
            fail(path, QStringLiteral("booleano esperado"));
        return v.toBool();
    }

    QString string(const QJsonValue &v, const QString &path)
    {
        if (!v.isString())
            fail(path, QStringLiteral("texto esperado"));
        return v.toString();
    }

    QUuid uuid(const QJsonValue &v, const QString &path)
    {
        const QUuid id = QUuid::fromString(string(v, path));
        if (id.isNull() && !failed())
            fail(path, QStringLiteral("UUID inválido"));
        return id;
    }

    template <typename E>
    E enumeration(const QJsonValue &v, const QString &path)
    {
        const auto e = enumFromKey<E>(string(v, path));
        if (!e) {
            fail(path, QStringLiteral("valor desconhecido \"%1\"").arg(v.toString()));
            return E(0);
        }
        return *e;
    }

    // Campos obrigatórios por chave.
    double number(const QJsonObject &o, const QString &path, const char *key)
    {
        return number(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    qint64 integer(const QJsonObject &o, const QString &path, const char *key)
    {
        return integer(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    bool boolean(const QJsonObject &o, const QString &path, const char *key)
    {
        return boolean(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    QString string(const QJsonObject &o, const QString &path, const char *key)
    {
        return string(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    QUuid uuid(const QJsonObject &o, const QString &path, const char *key)
    {
        return uuid(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    QJsonObject object(const QJsonObject &o, const QString &path, const char *key)
    {
        return object(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    QJsonArray array(const QJsonObject &o, const QString &path, const char *key)
    {
        return array(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }
    template <typename E>
    E enumeration(const QJsonObject &o, const QString &path, const char *key)
    {
        return enumeration<E>(required(o, path, key), path + u'.' + QLatin1StringView(key));
    }

    // Tipos compostos.
    TimeRange timeRange(const QJsonObject &o, const QString &path)
    {
        return {integer(o, path, "start"), integer(o, path, "duration")};
    }

    RGBA rgba(const QJsonObject &o, const QString &path)
    {
        return {number(o, path, "r"), number(o, path, "g"), number(o, path, "b"), number(o, path, "a")};
    }

    Transform transform(const QJsonObject &o, const QString &path)
    {
        return {number(o, path, "scale"), number(o, path, "x"), number(o, path, "y"), number(o, path, "rotation")};
    }

    Adjust adjust(const QJsonObject &o, const QString &path)
    {
        Adjust a;
        a.brightness = number(o, path, "brightness");
        a.contrast = number(o, path, "contrast");
        a.saturation = number(o, path, "saturation");
        a.exposure = number(o, path, "exposure");
        a.temperature = number(o, path, "temperature");
        a.tint = number(o, path, "tint");
        a.highlights = number(o, path, "highlights");
        a.shadows = number(o, path, "shadows");
        a.hue = number(o, path, "hue");
        a.sharpen = number(o, path, "sharpen");
        a.vignette = number(o, path, "vignette");
        a.fade = number(o, path, "fade");
        a.grain = number(o, path, "grain");
        return a;
    }

    /// Campos ausentes ficam com o padrão, como no `init(from:)` do `TextStyle` Swift.
    TextStyle textStyle(const QJsonObject &o, const QString &path)
    {
        TextStyle s;
        const auto opt = [&](const char *key, auto &field) {
            if (!present(o, key))
                return;
            const QString p = path + u'.' + QLatin1StringView(key);
            const QJsonValue v = o.value(QLatin1StringView(key));
            using T = std::decay_t<decltype(field)>;
            if constexpr (std::is_same_v<T, double>)
                field = number(v, p);
            else if constexpr (std::is_same_v<T, bool>)
                field = boolean(v, p);
            else if constexpr (std::is_same_v<T, QString>)
                field = string(v, p);
            else if constexpr (std::is_same_v<T, RGBA>)
                field = rgba(object(v, p), p);
            else
                field = enumeration<T>(v, p);
        };
        opt("fontName", s.fontName);
        opt("fontFace", s.fontFace);
        opt("fontSize", s.fontSize);
        opt("bold", s.bold);
        opt("italic", s.italic);
        opt("underline", s.underline);
        opt("textCase", s.textCase);
        opt("color", s.color);
        opt("opacity", s.opacity);
        opt("strokeColor", s.strokeColor);
        opt("strokeWidth", s.strokeWidth);
        opt("letterSpacing", s.letterSpacing);
        opt("lineSpacing", s.lineSpacing);
        opt("backgroundEnabled", s.backgroundEnabled);
        opt("backgroundColor", s.backgroundColor);
        opt("backgroundRadius", s.backgroundRadius);
        opt("backgroundPaddingX", s.backgroundPaddingX);
        opt("backgroundPaddingY", s.backgroundPaddingY);
        opt("shadow", s.shadow);
        opt("shadowColor", s.shadowColor);
        opt("shadowDistance", s.shadowDistance);
        opt("shadowAngle", s.shadowAngle);
        opt("shadowBlur", s.shadowBlur);
        opt("alignment", s.alignment);
        opt("x", s.x);
        opt("y", s.y);
        opt("scale", s.scale);
        opt("rotation", s.rotation);
        opt("maxWidth", s.maxWidth);
        return s;
    }

    Segment segment(const QJsonObject &o, const QString &path)
    {
        Segment s;
        s.id = uuid(o, path, "id");
        if (present(o, "materialId"))
            s.materialId = uuid(o, path, "materialId");
        s.source = timeRange(object(o, path, "source"), path + u".source");
        s.targetStart = integer(o, path, "targetStart");
        s.speed = number(o, path, "speed");
        s.volume = number(o, path, "volume");
        s.fadeIn = integer(o, path, "fadeIn");
        s.fadeOut = integer(o, path, "fadeOut");
        s.transform = transform(object(o, path, "transform"), path + u".transform");
        s.opacity = number(o, path, "opacity");
        s.adjust = adjust(object(o, path, "adjust"), path + u".adjust");
        if (present(o, "filter")) {
            const QString p = path + u".filter";
            const QJsonObject f = object(o, path, "filter");
            s.filter = FilterSetting{enumeration<FilterPreset>(f, p, "preset"), number(f, p, "intensity")};
        }
        const QJsonArray effects = array(o, path, "effects");
        for (int i = 0; i < effects.size(); ++i) {
            const QString p = path + QStringLiteral(".effects[%1]").arg(i);
            const QJsonObject e = object(effects[i], p);
            s.effects.append({uuid(e, p, "id"), enumeration<VideoEffectKind>(e, p, "kind"), number(e, p, "intensity")});
        }
        const auto animation = [&](const char *key) -> std::optional<SegmentAnimation> {
            if (!present(o, key))
                return std::nullopt;
            const QString p = path + u'.' + QLatin1StringView(key);
            const QJsonObject a = object(o, path, key);
            return SegmentAnimation{enumeration<AnimationKind>(a, p, "kind"), integer(a, p, "duration")};
        };
        s.animationIn = animation("animationIn");
        s.animationOut = animation("animationOut");
        if (present(o, "transition")) {
            const QString p = path + u".transition";
            const QJsonObject t = object(o, path, "transition");
            s.transition = Transition{enumeration<TransitionKind>(t, p, "kind"), integer(t, p, "duration")};
        }
        if (present(o, "text")) {
            const QString p = path + u".text";
            const QJsonObject t = object(o, path, "text");
            s.text = TextContent{string(t, p, "text"), textStyle(object(t, p, "style"), p + u".style")};
        }
        return s;
    }

    Track track(const QJsonObject &o, const QString &path)
    {
        Track t;
        t.id = uuid(o, path, "id");
        t.kind = enumeration<TrackKind>(o, path, "kind");
        t.isMain = boolean(o, path, "isMain");
        t.muted = boolean(o, path, "muted");
        t.hidden = boolean(o, path, "hidden");
        const QJsonArray segments = array(o, path, "segments");
        for (int i = 0; i < segments.size(); ++i) {
            const QString p = path + QStringLiteral(".segments[%1]").arg(i);
            t.segments.append(segment(object(segments[i], p), p));
        }
        return t;
    }

    Material material(const QJsonObject &o, const QString &path)
    {
        Material m;
        m.id = uuid(o, path, "id");
        m.kind = enumeration<MaterialKind>(o, path, "kind");
        m.path = string(o, path, "path");
        m.name = string(o, path, "name");
        m.duration = integer(o, path, "duration");
        m.width = int(integer(o, path, "width"));
        m.height = int(integer(o, path, "height"));
        m.hasAudio = boolean(o, path, "hasAudio");
        return m;
    }

    CanvasBackground background(const QJsonObject &o, const QString &path)
    {
        if (o.size() != 1) {
            fail(path, QStringLiteral("fundo inválido"));
            return CanvasBackground::black();
        }
        const QString key = o.constBegin().key();
        const QString p = path + u'.' + key;
        if (key == u"black") {
            object(o.constBegin().value(), p);
            return CanvasBackground::black();
        }
        if (key == u"color") {
            const QJsonObject c = object(o.constBegin().value(), p);
            return CanvasBackground::color(rgba(object(c, p, "_0"), p + u"._0"));
        }
        if (key == u"blur") {
            const QJsonObject b = object(o.constBegin().value(), p);
            return CanvasBackground::blur(number(b, p, "_0"));
        }
        fail(path, QStringLiteral("fundo desconhecido \"%1\"").arg(key));
        return CanvasBackground::black();
    }

    Project project(const QJsonObject &o)
    {
        const QString path = QStringLiteral("projeto");
        Project p;
        p.tracks.clear();
        p.formatVersion = int(integer(o, path, "formatVersion"));
        p.name = string(o, path, "name");
        const QJsonObject canvas = object(o, path, "canvas");
        p.canvas.aspect = enumeration<AspectRatio>(canvas, path + u".canvas", "aspect");
        p.canvas.background = background(object(canvas, path + u".canvas", "background"), path + u".canvas.background");
        p.fps = number(o, path, "fps");
        const QJsonArray materials = array(o, path, "materials");
        for (int i = 0; i < materials.size(); ++i) {
            const QString mp = path + QStringLiteral(".materials[%1]").arg(i);
            p.materials.append(material(object(materials[i], mp), mp));
        }
        const QJsonArray tracks = array(o, path, "tracks");
        for (int i = 0; i < tracks.size(); ++i) {
            const QString tp = path + QStringLiteral(".tracks[%1]").arg(i);
            p.tracks.append(track(object(tracks[i], tp), tp));
        }
        return p;
    }
};

} // namespace

std::optional<Project> fromJson(const QJsonObject &o, QString *error)
{
    Reader reader;
    Project p = reader.project(o);
    if (reader.failed()) {
        if (error)
            *error = reader.error;
        return std::nullopt;
    }
    return p;
}

std::optional<Project> decode(const QByteArray &data, QString *error)
{
    QJsonParseError parse;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parse);
    if (parse.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error)
            *error = parse.error != QJsonParseError::NoError ? parse.errorString()
                                                             : QStringLiteral("o arquivo não é um projeto");
        return std::nullopt;
    }
    return fromJson(doc.object(), error);
}

bool save(const Project &p, const QString &path, QString *error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(encode(p)) < 0 || !file.commit()) {
        if (error)
            *error = file.errorString();
        return false;
    }
    return true;
}

std::optional<Project> load(const QString &path, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (error)
            *error = file.errorString();
        return std::nullopt;
    }
    return decode(file.readAll(), error);
}

} // namespace of::ProjectStore
