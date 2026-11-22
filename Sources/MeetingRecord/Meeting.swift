import Foundation

struct Meeting: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date

    init(id: UUID, name: String, createdAt: Date) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              createdAt.timeIntervalSince1970.isFinite else {
            throw MeetingStoreError.invalidRecord
        }
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

enum MeetingStoreError: Error, LocalizedError {
    case invalidRecord, invalidDirectory, incompatibleVersion, sqlite(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidRecord: "O banco contém uma reunião inválida."
        case .invalidDirectory: "O diretório de dados precisa ser um caminho absoluto válido."
        case .incompatibleVersion: "A versão do banco não é compatível com este app."
        case .sqlite(let code): "Não foi possível acessar o armazenamento (SQLite \(code))."
        }
    }
}
