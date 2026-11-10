import Foundation

// MARK: - Server-Antworten (Immich v3.3.5, siehe API-NOTIZEN.md)

struct LoginResponse: Decodable {
    let accessToken: String
    let name: String
    let userId: String
    let userEmail: String
}

struct TimeBucket: Decodable, Hashable, Identifiable, Sendable {
    let timeBucket: String
    let count: Int
    var id: String { timeBucket }
    var monthDate: Date { DateParsing.day(timeBucket) ?? .distantPast }
}

struct BucketColumns: Decodable {
    let id: [String]
    let isImage: [Bool]
    let isFavorite: [Bool]
    let fileCreatedAt: [String]
    let localOffsetHours: [Double?]?
    let ratio: [Double?]
    let duration: [Int?]?
    let livePhotoVideoId: [String?]
    let city: [String?]?
    let country: [String?]?
    let thumbhash: [String?]?
    let createdAt: [String]?
    let ownerId: [String]?

    func assets() -> [Asset] {
        id.indices.map { i in
            ImageCache.shared.setHash(id[i], thumbhash?[i] ?? nil, video: !isImage[i])
            let utc = DateParsing.wallClock(fileCreatedAt[i]) ?? .distantPast
            let offset = (localOffsetHours?[i] ?? nil) ?? 0
            return Asset(id: id[i], isImage: isImage[i], isFavorite: isFavorite[i],
                         date: utc.addingTimeInterval(offset * 3600), ratio: ratio[i] ?? 1,
                         durationMs: duration?[i] ?? nil, livePhotoVideoId: livePhotoVideoId[i],
                         city: city?[i] ?? nil, country: country?[i] ?? nil,
                         addedAt: createdAt.flatMap { DateParsing.wallClock($0[i]) }, ownerId: ownerId?[i])
        }
    }
}

struct Asset: Identifiable, Hashable, Sendable {
    let id: String
    let isImage: Bool
    var isFavorite: Bool
    let date: Date
    let ratio: Double
    let durationMs: Int?
    let livePhotoVideoId: String?
    let city: String?
    let country: String?
    var addedAt: Date? = nil
    var ownerId: String? = nil
    var isHidden = false
    var trashedAt: Date? = nil
    var isVideo: Bool { !isImage }
    var isLivePhoto: Bool { livePhotoVideoId != nil }
}

struct AssetDTO: Decodable {
    let id: String
    let type: String
    let isFavorite: Bool
    let localDateTime: String?
    let fileCreatedAt: String
    let duration: Int?
    let livePhotoVideoId: String?
    let originalFileName: String?
    let originalMimeType: String?
    let exifInfo: ExifDTO?
    let createdAt: String?
    let ownerId: String?
    let isEdited: Bool?
    let description: String?
    let thumbhash: String?
    let width: Double?
    let height: Double?
    let stack: StackDTO?
    let visibility: String?
    let isTrashed: Bool?
    let people: [PersonDTO]?
    let updatedAt: String?
    struct StackDTO: Decodable { let id: String; let primaryAssetId: String?; let assetCount: Int? }

    struct ExifDTO: Decodable {
        let city: String?
        let country: String?
        let state: String?
        let make: String?
        let model: String?
        let exifImageWidth: Double?
        let exifImageHeight: Double?
        let fileSizeInByte: Int?
        let latitude: Double?
        let longitude: Double?
        let fNumber: Double?
        let focalLength: Double?
        let iso: Double?
        let exposureTime: String?
        let lensModel: String?
        let description: String?
        var dateTimeOriginal: String? = nil
    }

    var asset: Asset {
        ImageCache.shared.setHash(id, thumbhash, video: type != "IMAGE")
        let w = width ?? exifInfo?.exifImageWidth ?? 0, h = height ?? exifInfo?.exifImageHeight ?? 0
        return Asset(id: id, isImage: type == "IMAGE", isFavorite: isFavorite,
                     date: DateParsing.wallClock(localDateTime ?? fileCreatedAt) ?? .distantPast,
                     ratio: (w > 0 && h > 0) ? w / h : 1,
                     durationMs: (duration ?? 0) > 0 ? duration : nil,
                     livePhotoVideoId: livePhotoVideoId,
                     city: exifInfo?.city, country: exifInfo?.country,
                     addedAt: createdAt.flatMap(DateParsing.wallClock), ownerId: ownerId,
                     isHidden: visibility == "archive",
                     trashedAt: isTrashed == true ? (updatedAt.flatMap(DateParsing.wallClock) ?? Date()) : nil)
    }
}

struct MemoryDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let memoryAt: String
    let data: MemoryData
    let assets: [AssetDTO]
    struct MemoryData: Decodable { let year: Int? }
}

struct AlbumDTO: Decodable, Identifiable, Hashable {
    let id: String
    let albumName: String
    let albumThumbnailAssetId: String?
    let assetCount: Int
    var order: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var endDate: String? = nil
    var shared: Bool? = nil
}

struct ActivityDTO: Decodable, Identifiable, Hashable {
    struct User: Decodable, Hashable { let id: String; let name: String }
    let id: String
    let createdAt: String
    let type: String
    let assetId: String?
    let comment: String?
    let user: User
}

struct PersonDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let isHidden: Bool?
    var isFavorite: Bool? = nil
    var birthDate: String? = nil
}

struct PeopleDTO: Decodable {
    let people: [PersonDTO]
    let total: Int
}

struct MapMarkerDTO: Decodable, Identifiable {
    let id: String
    let lat: Double
    let lon: Double
    let city: String?
    let country: String?
}

struct TagDTO: Decodable {
    let id: String
    let value: String
}

struct DuplicateGroupDTO: Decodable, Identifiable {
    let duplicateId: String
    let assets: [AssetDTO]
    let suggestedKeepAssetIds: [String]?
    var id: String { duplicateId }
}

struct SearchResponseDTO: Decodable {
    struct Page: Decodable {
        let items: [AssetDTO]
        let nextCursor: String?
        let nextPage: String?
    }
    let assets: Page
}

struct UserDTO: Decodable {
    let id: String
    let name: String
    let email: String
}

struct ServerStatsDTO: Decodable {
    let images: Int?
    let videos: Int?
}

// MARK: - Datum

enum DateParsing {
    static let utc = TimeZone(identifier: "UTC")!

    private static let isoWall: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Parses the wall-clock portion and deliberately ignores a supplied timezone offset.
    /// Taking the fixed ISO timestamp prefix also handles negative offsets such as `-05:00`.
    static func wallClock(_ s: String) -> Date? {
        guard s.count >= 19 else { return nil }
        return isoWall.date(from: String(s.prefix(19)))
    }

    static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

extension Calendar {
    static let wall: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DateParsing.utc
        c.locale = .autoupdatingCurrent
        return c
    }()
}

enum Fmt {
    /// Use the app's selected localization rather than the device's region/system locale.
    static let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)

    private static func make(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = appLocale
        f.timeZone = DateParsing.utc
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    static let dayMonthYear = make("d MMM yyyy")
    static let monthYear = make("MMMM yyyy")
    static let monthShortYear = make("MMM yyyy")
    static let dayMonthYearShort = make("d MMM yyyy")
    static let weekdayDay = make("EEEE, d. MMMM")
    static let time = make("HH:mm")
    static let weekday = make("EEEE")
    static let dayMonthYearUpper = make("d MMM yyyy")
    static let dayLongMonthYear = make("d MMMM yyyy")
    static let fullDate = make("EEEE d MMMM yyyy")
    static let fullDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = appLocale
        f.timeZone = DateParsing.utc
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    static func relativeDay(_ d: Date, fallback: DateFormatter = dayLongMonthYear) -> String {
        let today = Calendar.wall.startOfDay(for: Date().addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT())))
        let diff = Calendar.wall.dateComponents([.day], from: Calendar.wall.startOfDay(for: d), to: today).day ?? 99
        switch diff {
        case 0: return String(localized: "Heute")
        case 1: return String(localized: "Gestern")
        case 2..<7: return weekday.string(from: d)
        default: return fallback.string(from: d)
        }
    }

    static func duration(_ ms: Int?) -> String {
        guard let ms else { return "" }
        let s = ms / 1000
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
