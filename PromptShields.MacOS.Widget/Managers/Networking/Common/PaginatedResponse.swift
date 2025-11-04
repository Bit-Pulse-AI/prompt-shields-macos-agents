struct PaginatedResponse<T: APIResponse>: SendableDecodable {
    typealias PaginatedType = T

    let items: [T]
    let total: Int
    let offset: Int
    let limit: Int

    init(items: [T], total: Int, offset: Int, limit: Int) {
        self.items = items
        self.total = total
        self.offset = offset
        self.limit = limit
    }

    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<PaginatedResponse<T>.CodingKeys> = try decoder.container(keyedBy: PaginatedResponse<T>.CodingKeys.self)
        self.items = try container.decode([T].self, forKey: PaginatedResponse<T>.CodingKeys.items)
        self.total = try container.decode(Int.self, forKey: PaginatedResponse<T>.CodingKeys.total)
        self.offset = try container.decode(Int.self, forKey: PaginatedResponse<T>.CodingKeys.offset)
        self.limit = try container.decode(Int.self, forKey: PaginatedResponse<T>.CodingKeys.limit)
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case offset
        case limit
    }

    func toDomain() -> [T.D] {
        items.compactMap {
            $0.toDomain()
        }
    }
}
