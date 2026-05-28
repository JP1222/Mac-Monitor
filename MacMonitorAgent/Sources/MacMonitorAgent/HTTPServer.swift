// HTTPServer.swift
//
// Minimal HTTP/1.1 server on NWListener. Just enough to:
//   - parse "GET /path HTTP/1.1" request lines
//   - serve a couple of routes
//   - return JSON or text bodies
//
// NO support for headers (beyond reading the request line), POST bodies,
// keep-alive, chunked encoding. That's deliberate — agents are LAN-only
// and serve at most a few req/min from a single trusted client.

import Foundation
import Network

final class HTTPServer {

    private let port: NWEndpoint.Port
    private let bindHost: NWEndpoint.Host
    private var listener: NWListener?
    // Serial queue for listener + connection events (accept, receive, send).
    private let queue = DispatchQueue(label: "macmonitor.agent.http", qos: .utility)
    // Concurrent queue for blocking route work (shell-outs). Keeps one slow
    // `docker` call from stalling the accept loop and other in-flight requests.
    private let workQueue = DispatchQueue(label: "macmonitor.agent.work", qos: .utility, attributes: .concurrent)

    init(port: UInt16, bindHost: String? = nil) {
        // Non-force-unwrap with an 8765 fallback (main.swift already maps 0 →
        // 8765, so this only guards against an unexpected nil).
        self.port = NWEndpoint.Port(rawValue: port) ?? 8765
        // Default loopback; an explicit address (e.g. a Tailscale IP) exposes
        // the agent on that one interface only.
        self.bindHost = bindHost.map { NWEndpoint.Host($0) } ?? .ipv4(.loopback)
    }

    func start() throws {
        let params = NWParameters.tcp
        // Pin the bind interface. Default is loopback (only this machine) —
        // without requiredLocalEndpoint NWListener would bind 0.0.0.0 (all
        // interfaces), exposing the mutating POST endpoints to the whole LAN.
        // `bindHost` can be set to a specific private address (e.g. a Tailscale
        // IP) to expose /health to another Mac on that mesh; POST stays
        // token-gated regardless.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: bindHost, port: port)
        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[macmonitor-agent] listening on port \(listener.port?.rawValue ?? 0)")
            case .failed(let err):
                print("[macmonitor-agent] listener failed: \(err)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        // Bound the HEADER-receive phase only (route handling in serve() may
        // legitimately take longer — e.g. a slow `docker system df`). A
        // stalled/slow-loris client that never completes its headers gets
        // dropped at the deadline.
        receive(connection: connection, accumulator: Data(), deadline: Date().addingTimeInterval(10))
    }

    /// Max header block we'll buffer before rejecting — guards against a
    /// client that streams bytes without ever sending the CRLFCRLF terminator.
    private static let maxHeaderBytes = 64 * 1024

    private func receive(connection: NWConnection, accumulator: Data, deadline: Date) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulator
            if let data { buffer.append(data) }

            // Look for the end of HTTP headers.
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = buffer[..<end.lowerBound]
                // Offload route handling (which may block on a shell-out) to
                // the concurrent work queue so the serial connection queue
                // stays free to accept + service other requests.
                self.workQueue.async { self.serve(requestHead: head, on: connection) }
                return
            }
            // Cap the buffer — never grow it without bound.
            if buffer.count > Self.maxHeaderBytes {
                self.respond(connection: connection, status: 400, body: Data("Request header too large".utf8), contentType: "text/plain")
                return
            }
            // Drop a connection that hasn't completed its headers in time.
            if Date() > deadline {
                connection.cancel()
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            // Need more bytes — keep reading.
            self.receive(connection: connection, accumulator: buffer, deadline: deadline)
        }
    }

    private func serve(requestHead: Data, on connection: NWConnection) {
        guard let headString = String(data: requestHead, encoding: .utf8) else {
            respond(connection: connection, status: 400, body: Data("Bad Request".utf8), contentType: "text/plain")
            return
        }
        // First line: "GET /path HTTP/1.1"
        let firstLine = headString.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            respond(connection: connection, status: 400, body: Data("Bad Request".utf8), contentType: "text/plain")
            return
        }
        let method = String(parts[0])
        // Strip any query string ("/health?ts=1" → "/health") before routing.
        let rawTarget = String(parts[1])
        let path = rawTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawTarget

        // Mutating endpoints require a Bearer token matching the shared secret
        // in the App Group container (written by the app). The loopback bind
        // already blocks the LAN; the token additionally defeats browser CSRF
        // to 127.0.0.1 and any other local process without the secret.
        func mutationAuthorized() -> Bool {
            AgentToken.validate(Self.bearerToken(in: headString))
        }

        // Routing.
        switch (method, path) {
        case ("GET", "/health"):
            let snapshot = DeviceHealthCollector.collect()
            respondJSON(connection: connection, status: 200, encoding: snapshot)
        case ("GET", "/"):
            let body = """
            MacMonitorAgent
            ───────────────
            GET  /health                  → DeviceSnapshot (JSON)
            POST /actions/prune-cache     → docker buildx prune -f
            POST /actions/restart-runners → kickstart all actions.runner.*

            Version 0.1
            """
            respond(connection: connection, status: 200, body: Data(body.utf8), contentType: "text/plain")
        case ("POST", "/actions/prune-cache"):
            guard mutationAuthorized() else {
                respond(connection: connection, status: 401, body: Data("Unauthorized".utf8), contentType: "text/plain")
                return
            }
            let r = AgentActions.pruneCache()
            respondJSON(connection: connection, status: r.ok ? 200 : 500, encoding: r)
        case ("POST", "/actions/restart-runners"):
            guard mutationAuthorized() else {
                respond(connection: connection, status: 401, body: Data("Unauthorized".utf8), contentType: "text/plain")
                return
            }
            let r = AgentActions.restartRunners()
            respondJSON(connection: connection, status: r.ok ? 200 : 500, encoding: r)
        case (_, _) where method != "GET" && method != "POST":
            respond(connection: connection, status: 405, body: Data("Method Not Allowed".utf8), contentType: "text/plain")
        default:
            respond(connection: connection, status: 404, body: Data("Not Found".utf8), contentType: "text/plain")
        }
    }

    /// Extract the `Authorization: Bearer <token>` value from the parsed
    /// request head (request line + headers, blank-line-terminated). Header
    /// names are case-insensitive per RFC 7230.
    private static func bearerToken(in headString: String) -> String? {
        for line in headString.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "authorization" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.lowercased().hasPrefix("bearer ") {
                return String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        return nil
    }

    private func respondJSON<T: Encodable>(connection: NWConnection, status: Int, encoding value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        respond(connection: connection, status: status, body: data, contentType: "application/json")
    }

    private func respond(connection: NWConnection, status: Int, body: Data, contentType: String) {
        let statusText: String = {
            switch status {
            case 200: return "OK"
            case 400: return "Bad Request"
            case 401: return "Unauthorized"
            case 404: return "Not Found"
            case 405: return "Method Not Allowed"
            case 500: return "Internal Server Error"
            default:  return "Status"
            }
        }()
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
