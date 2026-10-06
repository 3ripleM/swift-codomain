import Foundation
import Schema

// A todo-list domain that touches every library feature: string/number/bool/date codecs, enums,
// `nilIfEmpty` (OptionalField), optional nested objects, arrays of objects, and recursion (`subtasks`).

enum TodoFailure: Error, Equatable {
    case blank, tooLong, notASlug, notAnEmail, notADate, notPositive, notATimeZone
    case unknownPriority, unknownSort, unknownRepeat
}

private let text = Schema<String, String, TodoFailure>.identity

/// Case-insensitive `String` → enum.
private func oneOf<E: RawRepresentable & Sendable>(_ failure: TodoFailure) -> Codec<String, E, TodoFailure>
where E.RawValue == String {
    Codec(decode: text.trimmed().compactMap(failure) { E(rawValue: $0.lowercased()) }, encode: { $0.rawValue })
}

// MARK: - Field types

@Codec
struct Title: Hashable {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().nonEmpty(.blank).max(120, .tooLong),
        encode: { $0 }
    )
}

/// `weekend-plans`; trimmed and lowercased.
@Codec
struct Slug: Hashable {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().map { $0.lowercased() }.matches("^[a-z0-9]+(-[a-z0-9]+)*$", .notASlug),
        encode: { $0 }
    )
}

@Codec
struct Email: Hashable {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().map { $0.lowercased() }.matches(#"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, .notAnEmail),
        encode: { $0 }
    )
}

/// Blank → absent.
@Codec
struct Note {
    static let codec: Codec<String, String?, TodoFailure> = Codec(
        decode: text.trimmed().nilIfEmpty().max(500, .tooLong),
        encode: { $0 ?? "" }
    )
}

@Codec
struct Flag {
    static let codec: Codec<Bool, Bool, TodoFailure> = Codec(decode: .identity, encode: { $0 })
}

@Codec
struct Minutes {
    static let codec: Codec<Int, Int, TodoFailure> = Codec(
        decode: .identity.check(.notPositive) { $0 > 0 },
        encode: { $0 }
    )
}

@Codec
struct TimeZoneID {
    static let codec: Codec<String, TimeZone, TodoFailure> = Codec(
        decode: text.trimmed().compactMap(.notATimeZone) { TimeZone(identifier: $0) },
        encode: { $0.identifier }
    )
}

/// ISO 8601 text ↔ `Date`.
@Codec
struct Instant {
    static let codec: Codec<String, Date, TodoFailure> = Codec(
        decode: text.trimmed().compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
        encode: { $0.formatted(.iso8601) }
    )
}

@Codec
struct Priority {
    enum Level: String { case low, medium, high }
    static let codec: Codec<String, Level, TodoFailure> = oneOf(.unknownPriority)
}

@Codec
struct SortOrder {
    enum Order: String { case manual, due, priority }
    static let codec: Codec<String, Order, TodoFailure> = oneOf(.unknownSort)
}

@Codec
struct Repeat {
    enum Every: String { case never, daily, weekly }
    static let codec: Codec<String, Every, TodoFailure> = oneOf(.unknownRepeat)
}

// MARK: - Models

@JSONSchema(failure: TodoFailure.self)
struct Member {
    let email: Email
    let name: Title
}

@JSONSchema(failure: TodoFailure.self)
struct Settings {
    let sort: SortOrder
    let reminderDefault: Minutes?
    let timezone: TimeZoneID
}

@JSONSchema(failure: TodoFailure.self)
struct Reminder {
    let at: Instant
    let repeats: Repeat
}

@JSONSchema(failure: TodoFailure.self)
struct Todo {
    let title: Title
    let done: Flag
    let priority: Priority
    let due: Instant?
    let note: Note?
    let tags: [Slug]
    let reminder: Reminder?
    let subtasks: [Todo]  // recursive
}

@JSONSchema(failure: TodoFailure.self)
struct TodoList {
    let title: Title
    let slug: Slug
    let owner: Member
    let sharedWith: [Member]
    let settings: Settings
    let items: [Todo]
}
