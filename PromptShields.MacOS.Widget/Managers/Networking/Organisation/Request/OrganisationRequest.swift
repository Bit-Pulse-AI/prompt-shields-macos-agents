import Foundation

struct CreateOrganisationRequest: SendableEncodable {
    private let name: String
    private let description: String?

    init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
    }
}

struct UpdateOrganisationRequest: SendableEncodable {
    private let name: String?
    private let description: String?

    init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
    }
}
