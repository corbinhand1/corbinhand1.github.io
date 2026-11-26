//
//  GitHubPublisher.swift
//  Cue to Cue
//
//  Writes website files to a GitHub repository as ONE commit using the Git
//  Data API (blobs → tree → commit → move branch).
//
//  Why not the Contents API (one PUT per file, which earlier builds used):
//  - Each file was its own commit, so a failure part-way left the site
//    inconsistent (metadata said one show while the data was another).
//  - Updating a file needs its current SHA, read with GET /contents. GitHub
//    does not serve files over 1 MB in that format, so once the cue data
//    passed 1 MB every update was rejected.
//  - GET responses are cacheable for 60 s, so a second publish within a
//    minute read a stale SHA and failed with a conflict.
//  Here every request bypasses the cache, file size never matters (blobs go
//  up to 100 MB), and all files land together or not at all.
//

import Foundation

struct GitHubRepository: Equatable, CustomStringConvertible {
    var owner: String
    var name: String
    var description: String { "\(owner)/\(name)" }
}

enum GitHubError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case rateLimited(resetAt: Date?)
    case conflict
    case network(String)
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add a GitHub token in Website settings before publishing."
        case .unauthorized(let message):
            return "GitHub rejected the token (\(message)). It may have expired or been revoked. Create a new token with the \u{201C}repo\u{201D} scope and paste it in Website settings."
        case .forbidden(let message):
            return "The token can't write to this repository (\(message)). Check that it has the \u{201C}repo\u{201D} scope and access to the repository."
        case .notFound(let what):
            return "\(what) wasn't found on GitHub. Check the owner and repository name in Website settings."
        case .rateLimited(let resetAt):
            if let resetAt {
                let f = DateFormatter()
                f.timeStyle = .short
                return "GitHub's rate limit was reached. Try again after \(f.string(from: resetAt))."
            }
            return "GitHub's rate limit was reached. Try again in a few minutes."
        case .conflict:
            return "The website changed on GitHub while publishing, three times in a row. Publish again."
        case .network(let message):
            return "Couldn't reach GitHub: \(message)"
        case .http(let code, let message):
            return "GitHub returned an error (\(code)): \(message)"
        case .invalidResponse:
            return "GitHub sent a response the app couldn't read."
        }
    }
}

/// A file to add, replace or remove in the commit.
enum GitHubFileChange: Equatable {
    case write(path: String, data: Data)
    case delete(path: String)

    var path: String {
        switch self {
        case .write(let path, _), .delete(let path): return path
        }
    }
}

struct GitHubCommitResult: Equatable {
    let sha: String
    let htmlURL: URL?
}

struct GitHubConnectionInfo: Equatable {
    let login: String
    let canPush: Bool
    let defaultBranch: String
}

final class GitHubPublisher {
    let repository: GitHubRepository
    private let token: String
    private let session: URLSession
    private let apiBase: URL
    private var cachedDefaultBranch: String?

    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        if let protocolClasses {
            config.protocolClasses = protocolClasses
        }
        return URLSession(configuration: config)
    }

    init(token: String,
         repository: GitHubRepository,
         session: URLSession = GitHubPublisher.makeSession(),
         apiBase: URL = URL(string: "https://api.github.com")!) {
        self.token = token
        self.repository = repository
        self.session = session
        self.apiBase = apiBase
    }

    // MARK: - Public API

    /// Check the token and repository access.
    func validate() async throws -> GitHubConnectionInfo {
        let user = try await requestJSON("GET", "/user")
        guard let login = user["login"] as? String else { throw GitHubError.invalidResponse }
        let repo = try await requestJSON("GET", "/repos/\(repository.owner)/\(repository.name)", notFoundName: "Repository \(repository)")
        let permissions = repo["permissions"] as? [String: Any]
        let branch = repo["default_branch"] as? String ?? "main"
        cachedDefaultBranch = branch
        return GitHubConnectionInfo(login: login, canPush: permissions?["push"] as? Bool ?? false, defaultBranch: branch)
    }

    /// Read a file's raw bytes (any size). Returns nil when it doesn't exist.
    func readFile(_ path: String) async throws -> Data? {
        do {
            let (data, _) = try await send("GET", "/repos/\(repository.owner)/\(repository.name)/contents/\(escape(path))",
                                           accept: "application/vnd.github.raw+json")
            return data
        } catch GitHubError.notFound {
            return nil
        }
    }

    /// Apply all changes as a single commit on the default branch. Retries
    /// up to three times if the branch moves while committing.
    func commit(_ changes: [GitHubFileChange], message: String) async throws -> GitHubCommitResult {
        precondition(!changes.isEmpty, "commit needs at least one change")
        let branch = try await defaultBranch()

        // Upload file contents once; blob SHAs stay valid across retries.
        var blobs: [String: String] = [:]
        for change in changes {
            if case .write(let path, let data) = change {
                let blob = try await requestJSON("POST", "/repos/\(repository.owner)/\(repository.name)/git/blobs",
                                                 body: ["content": data.base64EncodedString(), "encoding": "base64"])
                guard let sha = blob["sha"] as? String else { throw GitHubError.invalidResponse }
                blobs[path] = sha
            }
        }

        for _ in 0..<3 {
            let ref = try await requestJSON("GET", "/repos/\(repository.owner)/\(repository.name)/git/ref/heads/\(branch)",
                                            notFoundName: "Branch \(branch)")
            guard let headSHA = (ref["object"] as? [String: Any])?["sha"] as? String else { throw GitHubError.invalidResponse }

            let headCommit = try await requestJSON("GET", "/repos/\(repository.owner)/\(repository.name)/git/commits/\(headSHA)")
            guard let baseTree = (headCommit["tree"] as? [String: Any])?["sha"] as? String else { throw GitHubError.invalidResponse }

            let entries: [[String: Any]] = changes.map { change in
                switch change {
                case .write(let path, _):
                    return ["path": path, "mode": "100644", "type": "blob", "sha": blobs[path]!]
                case .delete(let path):
                    return ["path": path, "mode": "100644", "type": "blob", "sha": NSNull()]
                }
            }
            let tree = try await requestJSON("POST", "/repos/\(repository.owner)/\(repository.name)/git/trees",
                                             body: ["base_tree": baseTree, "tree": entries])
            guard let treeSHA = tree["sha"] as? String else { throw GitHubError.invalidResponse }

            let newCommit = try await requestJSON("POST", "/repos/\(repository.owner)/\(repository.name)/git/commits",
                                                  body: ["message": message, "tree": treeSHA, "parents": [headSHA]])
            guard let commitSHA = newCommit["sha"] as? String else { throw GitHubError.invalidResponse }

            do {
                _ = try await requestJSON("PATCH", "/repos/\(repository.owner)/\(repository.name)/git/refs/heads/\(branch)",
                                          body: ["sha": commitSHA, "force": false])
                let html = (newCommit["html_url"] as? String).flatMap(URL.init(string:))
                return GitHubCommitResult(sha: commitSHA, htmlURL: html)
            } catch let error as GitHubError {
                // 422 "not a fast forward" / 409: someone else committed. Rebuild on the new head.
                if case .http(let code, _) = error, code == 422 || code == 409 { continue }
                if case .conflict = error { continue }
                throw error
            }
        }
        throw GitHubError.conflict
    }

    // MARK: - Requests

    private func defaultBranch() async throws -> String {
        if let cachedDefaultBranch { return cachedDefaultBranch }
        let repo = try await requestJSON("GET", "/repos/\(repository.owner)/\(repository.name)", notFoundName: "Repository \(repository)")
        let branch = repo["default_branch"] as? String ?? "main"
        cachedDefaultBranch = branch
        return branch
    }

    private func escape(_ path: String) -> String {
        path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String($0)
        }.joined(separator: "/")
    }

    private func requestJSON(_ method: String, _ path: String, body: [String: Any]? = nil, notFoundName: String? = nil) async throws -> [String: Any] {
        let (data, _) = try await send(method, path, body: body, notFoundName: notFoundName)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.invalidResponse
        }
        return object
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil,
                      accept: String = "application/vnd.github+json",
                      notFoundName: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: apiBase.absoluteString + path) else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Cue-to-Cue", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            switch http.statusCode {
            case 401:
                throw GitHubError.unauthorized(message)
            case 403, 429:
                if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http.statusCode == 429 {
                    let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                    throw GitHubError.rateLimited(resetAt: reset)
                }
                throw GitHubError.forbidden(message)
            case 404:
                throw GitHubError.notFound(notFoundName ?? "The requested item")
            default:
                throw GitHubError.http(http.statusCode, message)
            }
        }
    }
}
