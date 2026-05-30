import Foundation

public final class ReportService: @unchecked Sendable {

    // MARK: - Public

    public var onError: (@Sendable (Error) -> Void)?

    // MARK: - Private state (accessed only on queue)

    private var fileHandle: FileHandle?
    private var currentFilePath: URL?
    private let queue = DispatchQueue(label: "minto.report", qos: .utility)

    private var flushObserver: NSObjectProtocol?

    // MARK: - Init

    public init() {}

    deinit {
        if let observer = flushObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    public func startNewReport(startedAt: Date) {
        // Close any existing report first
        finalizeReport()

        let mintoDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Minto", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: mintoDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let fileName = "\(formatter.string(from: startedAt)).md"
        let filePath = mintoDir.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: filePath.path) {
            FileManager.default.createFile(atPath: filePath.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: filePath)
            handle.seekToEndOfFile()
            fileHandle = handle
            currentFilePath = filePath
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
            return
        }

        // Register for flush notification
        let observer = NotificationCenter.default.addObserver(
            forName: .transcriptionNeedsFlush,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let segments = notification.object as? [Segment] {
                for segment in segments {
                    self?.appendSegment(segment)
                }
            }
        }
        flushObserver = observer
    }

    public func appendSegment(_ segment: Segment) {
        queue.async { [weak self] in
            guard let self, let handle = self.fileHandle else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: segment.timestamp)
            let line = "[\(timeString)] \(segment.text)\n"

            guard let data = line.data(using: .utf8) else { return }

            do {
                try handle.write(contentsOf: data)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        }
    }

    public func finalizeReport() {
        if let observer = flushObserver {
            NotificationCenter.default.removeObserver(observer)
            flushObserver = nil
        }

        queue.sync { [weak self] in
            guard let self else { return }
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.currentFilePath = nil
        }
    }
}
