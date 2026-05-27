// Repository.swift
//
// A GitHub repository the user wants to monitor. Multiple repositories can
// share the same self-hosted runner pool, so this is its own first-class
// entity (rather than a string field on Runner/Job).

import Foundation

public struct Repository: Codable, Identifiable, Hashable, Sendable {
    /// Slug form `owner/name`, e.g. `JP1222/yolo-rollo`.
    public var id: String { "\(owner)/\(name)" }
    public let owner: String
    public let name: String
    public var defaultBranch: String

    public init(owner: String, name: String, defaultBranch: String = "main") {
        self.owner = owner
        self.name = name
        self.defaultBranch = defaultBranch
    }

    /// Convenience for human display ("owner/name").
    public var slug: String { id }

    /// URL to the repo's Actions tab — used by the "View all on GitHub" link
    /// in the popover footer.
    public var actionsURL: URL? {
        URL(string: "https://github.com/\(owner)/\(name)/actions")
    }
}
