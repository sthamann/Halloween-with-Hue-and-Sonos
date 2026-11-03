import Foundation

/// Stream response headers and data immediately. URLSession.bytes can delay its
/// initial response on an idle Hue SSE connection; data-delegate callbacks do not.
final class HueEventStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Message: Sendable { case connected, data(Data) }
    private let tls: HueTLS
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Message, Error>.Continuation?
    private var session: URLSession?
    init(bridgeID: String) { tls = HueTLS(bridgeID: bridgeID) }

    func open(_ request: URLRequest) -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(64)) { continuation in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 90
            config.timeoutIntervalForResource = 86_400
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            lock.lock(); self.continuation = continuation; self.session = session; lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.stop() }
            session.dataTask(with: request).resume()
        }
    }
    func stop() { finish(CancellationError()) }
    private func finish(_ error: Error) {
        lock.lock(); let continuation = self.continuation, session = self.session
        self.continuation = nil; self.session = nil; lock.unlock()
        continuation?.finish(throwing: error)
        session?.invalidateAndCancel()
    }
    private func yield(_ message: Message) {
        lock.lock(); let continuation = self.continuation; lock.unlock()
        if case .dropped = continuation?.yield(message) {
            finish(AppFailure(L10n.value("Hue-Ereignisse kommen schneller an, als sie verarbeitet werden können. Verbindung wird neu aufgebaut.")))
        }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        tls.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
            completionHandler(.cancel); finish(AppFailure(L10n.value("Hue-Ereignisstrom nicht erreichbar."))); return
        }
        completionHandler(.allow)
        yield(.connected)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { yield(.data(data)) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error ?? AppFailure(L10n.value("Hue-Verbindung unterbrochen.")))
    }
}
