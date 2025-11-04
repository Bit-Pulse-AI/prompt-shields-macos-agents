import Foundation

struct CreateTeamRequest: SendableEncodable {
    private let name: String

    init(name: String) {
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case name
    }
}

enum TeamStatusRequest: SendableEncodable {
    case active
    case suspended
    case archived
}

struct UpdateTeamRequest: SendableEncodable {
    private let name: String?
    private let teamStatus: TeamStatusRequest?

    init(name: String? = nil, teamStatus: TeamStatusRequest? = nil) {
        self.name = name
        self.teamStatus = teamStatus
    }

    enum CodingKeys: String, CodingKey {
        case name
        case teamStatus = "team_status"
    }
}
