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
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "macmonitor.agent.http", qos: .utility)

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[macmonitor-agent] listening on http://127.0.0.1:\(listener.port?.rawValue ?? 0)")
            case .failed(let err):
                print("[macmonitor-agent] listener failed: \(err)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection: connection, accumulator: Data())
    }

    private func receive(connection: NWConnection, accumulator: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulator
            if let data { buffer.append(data) }

            // Look for the end of HTTP headers.
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = buffer[..<end.lowerBound]
                self.serve(requestHead: head, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            // Need more bytes — keep reading.
            self.receive(connection: connection, accumulator: buffer)
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
        guard parts.count >= 2, parts[0] == "GET" else {
            respond(connection: connection, status: 405, body: Data("Method Not Allowed".utf8), contentType: "text/plain")
            return
        }
        let path = String(parts[1])

        switch path {
        case "/health":
            let snapshot = DeviceHealthCollector.collect()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
            respond(connection: connection, status: 200, body: data, contentType: "application/json")
        case "/":
            let body = """
            MacMonitorAgent
            ───────────────
            GET /health   →  Current DeviceSnapshot as JSON

            Version 0.1
            """
            respond(connection: connection, status: 200, body: Data(body.utf8), contentType: "text/plain")
        default:
            respond(connection: connection, status: 404, body: Data("Not Found".utf8), contentType: "text/plain")
        }
    }

    private func respond(connection: NWConnection, status: Int, body: Data, contentType: String) {
        let statusText: String = {
            switch status {
            case 200: return "OK"
            case 400: return "Bad Request"
            case 404: return "Not Found"
            case 405: return "Method Not Allowed"
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
