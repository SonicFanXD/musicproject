import SwiftUI

/// ✅ PLAYLISTS AUTOMÁTICAS (3.0): se calculan AL VUELO cada vez que se abren.
/// No se persisten, NO se añaden a `playlists` del usuario y no tocan el caché
/// de biblioteca: son consultas sobre `songs` + las estadísticas de
/// reproducción de FileAccessService.
struct SmartPlaylist: Identifiable {
    let id: String
    /// Clave de Localization del nombre.
    let nameKey: String
    /// SF Symbol de la card.
    let icon: String
    /// Tinte sugerido para el gradiente de la card.
    let colorHint: Color
    /// Consulta: recibe el servicio y devuelve las canciones de esta playlist.
    let songs: (FileAccessService) -> [Song]

    var name: String { Localization.localized(nameKey) }

    func songs(from service: FileAccessService) -> [Song] { songs(service) }
}

extension SmartPlaylist {
    /// ✅ Las 5 playlists automáticas, en el orden del carrusel de Bienvenida.
    static let all: [SmartPlaylist] = [topPlayed, discoveries, sleepFriendly, dailyMix, weeklyMix]

    // MARK: - 1. Lo más escuchado

    /// ✅ Top 50 por reproducciones iniciadas. Solo se tienen en cuenta las
    /// canciones que sonaron en los últimos 30 días: no guardamos el historial
    /// completo de cada reproducción, así que la ventana se aplica sobre la
    /// ÚLTIMA vez que sonó (decisión aprobada en el diagnóstico).
    /// Biblioteca nueva (nada reproducido todavía) → vacío, y la UI muestra
    /// `smart.empty` en su lugar.
    static let topPlayed = SmartPlaylist(
        id: "smart.topPlayed",
        nameKey: "smart.topPlayed",
        icon: "flame.fill",
        colorHint: Color(red: 0.96, green: 0.36, blue: 0.24),
        songs: { service in
            let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
            let recent = service.songs.filter { song in
                guard let last = service.lastPlayed(for: song.id) else { return false }
                return last >= cutoff
            }
            let ranked = recent.sorted { service.playCount(for: $0.id) > service.playCount(for: $1.id) }
            return Array(ranked.prefix(50))
        }
    )

    // MARK: - 2. Descubrimientos

    /// ✅ Canciones casi no escuchadas (≤ 2 reproducciones), las más recientes
    /// primero. "Reciente" usa la fecha de modificación del archivo como proxy
    /// de la fecha de agregado (Song no guarda cuándo entró a la biblioteca).
    static let discoveries = SmartPlaylist(
        id: "smart.discoveries",
        nameKey: "smart.discoveries",
        icon: "sparkles",
        colorHint: Color(red: 0.62, green: 0.40, blue: 0.95),
        songs: { service in
            let fresh = service.songs
                .filter { service.playCount(for: $0.id) <= 2 }
                .sorted { SmartPlaylist.recency($0) > SmartPlaylist.recency($1) }
            return Array(fresh.prefix(100))
        }
    )

    // MARK: - 3. Para dormir

    /// ✅ Heurística sin BPM ni análisis de audio: material de muestreo "ligero"
    /// (< 48 kHz, típico de ediciones suaves) y de más de 4 minutos.
    static let sleepFriendly = SmartPlaylist(
        id: "smart.sleep",
        nameKey: "smart.sleep",
        icon: "moon.stars.fill",
        colorHint: Color(red: 0.35, green: 0.32, blue: 0.72),
        songs: { service in
            service.songs
                .filter { $0.sampleRate > 0 && $0.sampleRate < 48_000 && $0.duration > 240 }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    )

    // MARK: - 4. Mezcla diaria

    /// ✅ 30 canciones deterministas por DÍA (misma mezcla durante todo el día,
    /// distinta al siguiente).
    static let dailyMix = SmartPlaylist(
        id: "smart.dailyMix",
        nameKey: "smart.dailyMix",
        icon: "sun.max.fill",
        colorHint: Color(red: 0.20, green: 0.55, blue: 0.95),
        songs: { service in
            composeMix(service: service, seed: stableSeed(dayKey()), count: 30)
        }
    )

    // MARK: - 5. Mezcla semanal

    /// ✅ Igual que la diaria pero con semilla de semana ISO y 50 canciones.
    static let weeklyMix = SmartPlaylist(
        id: "smart.weeklyMix",
        nameKey: "smart.weeklyMix",
        icon: "calendar.badge.clock",
        colorHint: Color(red: 0.10, green: 0.75, blue: 0.50),
        songs: { service in
            composeMix(service: service, seed: stableSeed(weekKey()), count: 50)
        }
    )

    // MARK: - Composición de las mezclas

    /// ✅ 40% lo más escuchado + 30% "me gusta" + 30% descubrimientos, completando
    /// con la biblioteca si aún faltan canciones (biblioteca nueva o historial
    /// corto). El orden final se baraja con el generador SEMBRADO por día/semana.
    static func composeMix(service: FileAccessService, seed: UInt64, count: Int) -> [Song] {
        var generator = SeededGenerator(seed: seed)
        var picked: [Song] = []
        var seen = Set<UUID>()
        let topLimit = max(1, Int(Double(count) * 0.4))
        let likedLimit = max(topLimit, Int(Double(count) * 0.7))

        append(&picked, from: topPlayed.songs(service), upTo: topLimit, seen: &seen)
        append(&picked, from: service.likedSongs.shuffled(using: &generator), upTo: likedLimit, seen: &seen)
        append(&picked, from: discoveries.songs(service).shuffled(using: &generator), upTo: count, seen: &seen)
        if picked.count < count {
            append(&picked, from: service.songs.shuffled(using: &generator), upTo: count, seen: &seen)
        }
        return picked.shuffled(using: &generator)
    }

    private static func append(_ picked: inout [Song], from candidates: [Song], upTo limit: Int, seen: inout Set<UUID>) {
        guard picked.count < limit else { return }
        for song in candidates {
            guard picked.count < limit else { return }
            guard seen.insert(song.id).inserted else { continue }
            picked.append(song)
        }
    }

    /// ✅ Proxy de "fecha de agregado": la fecha de modificación del archivo en
    /// disco (lo más cercano a "archivo reciente") y, como respaldo, la fecha de
    /// publicación del álbum.
    static func recency(_ song: Song) -> Date {
        song.fileModificationDate ?? song.releaseDate ?? .distantPast
    }

    // MARK: - Semillas deterministas

    /// ✅ PRNG determinista (SplitMix64). Hace falta uno propio porque
    /// `String.hashValue` está aleatorizado POR PROCESO en Swift: usarlo daría
    /// una "mezcla diaria" distinta en cada arranque de la app.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// ✅ Hash estable entre ejecuciones (FNV-1a 64 bits) para sembrar con la fecha.
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Clave del día actual ("2026-09-21").
    static func dayKey(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    /// Clave de la semana ISO actual ("2026-W38").
    static func weekKey(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
}
