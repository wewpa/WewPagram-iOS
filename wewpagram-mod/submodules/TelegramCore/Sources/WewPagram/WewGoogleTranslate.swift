import Foundation
import SwiftSignalKit

// Translation of incoming messages without Telegram Premium: the text goes to
// the public Google Translate endpoint (the same one Telegram itself uses for
// its "alternative" translation mode). Formatting entities are not carried over.
public final class WewGoogleTranslationService: ExperimentalInternalTranslationService {
    public static let shared = WewGoogleTranslationService()

    private init() {}

    private static func normalize(_ code: String) -> String {
        let lower = code.lowercased()
        switch lower {
        case "zh-hans", "zh":
            return "zh-CN"
        case "zh-hant":
            return "zh-TW"
        case "nb":
            return "no"
        default:
            if let first = lower.split(separator: "-").first, lower.contains("-") {
                return String(first)
            }
            return lower
        }
    }

    // Splits long text on line breaks so that every request stays small.
    private static func chunks(of text: String, limit: Int = 3500) -> [String] {
        if text.count <= limit {
            return [text]
        }
        var result: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if !current.isEmpty && current.count + line.count + 1 > limit {
                result.append(current)
                current = ""
            }
            if line.count > limit {
                var rest = Substring(line)
                while !rest.isEmpty {
                    let part = rest.prefix(limit)
                    result.append(String(part))
                    rest = rest.dropFirst(part.count)
                }
                continue
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func requestChunk(_ chunk: String, from: String, to: String, completion: @escaping (String?) -> Void) -> URLSessionTask? {
        guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(chunk)
            return nil
        }
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from),
            URLQueryItem(name: "tl", value: to),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8")
        ]
        guard let url = components.url else {
            completion(nil)
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 15.0)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = chunk.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = ("q=" + encoded).data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
                  let blocks = json.first as? [Any] else {
                completion(nil)
                return
            }
            var out = ""
            for block in blocks {
                if let parts = block as? [Any], let piece = parts.first as? String {
                    out += piece
                }
            }
            completion(out)
        }
        task.resume()
        return task
    }

    public func translate(texts: [AnyHashable: String], fromLang: String, toLang: String) -> Signal<[AnyHashable: String]?, NoError> {
        return Signal { subscriber in
            let lock = NSLock()
            var tasks: [URLSessionTask] = []
            var cancelled = false
            var results: [AnyHashable: String] = [:]
            var failed = false

            let from = fromLang.isEmpty ? "auto" : WewGoogleTranslationService.normalize(fromLang)
            let to = WewGoogleTranslationService.normalize(toLang)
            let group = DispatchGroup()

            for (key, text) in texts {
                let parts = WewGoogleTranslationService.chunks(of: text)
                group.enter()
                var translated: [String] = []
                func next(_ index: Int) {
                    lock.lock()
                    let stop = cancelled
                    lock.unlock()
                    if stop || index >= parts.count {
                        lock.lock()
                        if index >= parts.count && !stop {
                            results[key] = translated.joined(separator: "\n")
                        }
                        lock.unlock()
                        group.leave()
                        return
                    }
                    let task = WewGoogleTranslationService.requestChunk(parts[index], from: from, to: to, completion: { piece in
                        if let piece = piece {
                            translated.append(piece)
                            next(index + 1)
                        } else {
                            lock.lock()
                            failed = true
                            lock.unlock()
                            group.leave()
                        }
                    })
                    if let task = task {
                        lock.lock()
                        tasks.append(task)
                        lock.unlock()
                    }
                }
                next(0)
            }

            group.notify(queue: .global()) {
                lock.lock()
                let isCancelled = cancelled
                let isFailed = failed
                let output = results
                lock.unlock()
                if isCancelled {
                    return
                }
                subscriber.putNext(isFailed ? nil : output)
                subscriber.putCompletion()
            }

            return ActionDisposable {
                lock.lock()
                cancelled = true
                let pending = tasks
                lock.unlock()
                for task in pending {
                    task.cancel()
                }
            }
        }
    }
}
