struct ListResponse<T: APIResponse>: SendableDecodable {
    typealias PaginatedType = T

    let items: [T]

    init(items: [T]) {
        self.items = items
    }

    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<PaginatedResponse<T>.CodingKeys> = try decoder.container(keyedBy: PaginatedResponse<T>.CodingKeys.self)
        self.items = try container.decode([T].self, forKey: PaginatedResponse<T>.CodingKeys.items)
    }

    enum CodingKeys: String, CodingKey {
        case items
    }

    func toDomain() -> [T.D] {
        items.compactMap {
            $0.toDomain()
        }
    }
}
