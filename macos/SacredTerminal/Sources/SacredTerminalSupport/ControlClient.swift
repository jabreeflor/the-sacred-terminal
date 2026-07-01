import Darwin
import Foundation

public enum SacredTerminalControlClientError: Error, CustomStringConvertible {
    case connect(path: String, errno: Int32)
    case notRunning(path: String)
    case write(errno: Int32)
    case eof
    case badReply(String)
    case badCommand(String)

    public var description: String {
        switch self {
        case .connect(let path, let error):
            return "could not connect to \(path): \(String(cString: strerror(error)))"
        case .notRunning(let path):
            return "The Sacred Terminal does not appear to be running (no socket at \(path)). Launch the app first."
        case .write(let error):
            return "write failed: \(String(cString: strerror(error)))"
        case .eof:
            return "connection closed before a reply was received"
        case .badReply(let string):
            return "unexpected reply from app: \(string)"
        case .badCommand(let string):
            return string
        }
    }
}

/// A blocking one-command client for the app's Unix-domain JSON control socket.
public final class SacredTerminalControlClient {
    private let fd: Int32
    private let path: String

    public init(path: String = SacredTerminalRuntime.controlSocketURL.path) throws {
        self.path = path

        if !FileManager.default.fileExists(atPath: path) {
            throw SacredTerminalControlClientError.notRunning(path: path)
        }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw SacredTerminalControlClientError.connect(path: path, errno: errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(sock)
            throw SacredTerminalControlClientError.connect(path: path, errno: ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (index, byte) in pathBytes.enumerated() {
                    dst[index] = CChar(bitPattern: byte)
                }
                dst[pathBytes.count] = 0
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = errno
            close(sock)
            if error == ECONNREFUSED || error == ENOENT || error == ENOTSOCK {
                throw SacredTerminalControlClientError.notRunning(path: path)
            }
            throw SacredTerminalControlClientError.connect(path: path, errno: error)
        }

        fd = sock
    }

    deinit {
        close(fd)
    }

    public func request(_ command: [String: Any]) throws -> [String: Any] {
        try writeLine(command)
        let line = try readLine()
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            throw SacredTerminalControlClientError.badReply(String(decoding: line, as: UTF8.self))
        }
        return object
    }

    private func writeLine(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            throw SacredTerminalControlClientError.badCommand("could not encode command")
        }

        data.append(0x0A)
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                if written <= 0 {
                    if written < 0 && errno == EINTR { continue }
                    throw SacredTerminalControlClientError.write(errno: errno)
                }
                offset += written
            }
        }
    }

    private func readLine() throws -> Data {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            if count == 0 {
                if !buffer.isEmpty { return trimCR(buffer) }
                throw SacredTerminalControlClientError.eof
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw SacredTerminalControlClientError.write(errno: errno)
            }
            buffer.append(contentsOf: chunk[0..<count])
            if let newline = buffer.firstIndex(of: 0x0A) {
                return trimCR(buffer.subdata(in: buffer.startIndex..<newline))
            }
        }
    }

    private func trimCR(_ data: Data) -> Data {
        guard data.last == 0x0D else { return data }
        return data.subdata(in: data.startIndex..<data.index(before: data.endIndex))
    }
}
