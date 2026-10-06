import Foundation

/// Mocked server. Knows nothing about `User`: stores JSON bodies in an array, unique by `email`.
final class Backend {
    enum Failure: Error, Equatable { case duplicateEmail, malformedBody }

    private struct Key: Decodable { let email: String }
    private var rows: [(email: String, body: Data)] = []

    func insert(_ body: Data) -> Result<Void, Failure> {
        guard let key = try? JSONDecoder().decode(Key.self, from: body) else { return .failure(.malformedBody) }
        guard !rows.contains(where: { $0.email == key.email }) else { return .failure(.duplicateEmail) }
        rows.append((key.email, body))
        return .success(())
    }

    func find(email: String) -> Data? {
        rows.first { $0.email == email }?.body
    }
}
