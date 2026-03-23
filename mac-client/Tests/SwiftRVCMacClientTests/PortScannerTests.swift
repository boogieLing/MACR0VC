import Darwin
import XCTest
@testable import SwiftRVCMacClient

final class PortScannerTests: XCTestCase {
    func testFindsNextPortWhenPreferredPortIsOccupied() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(socketFD, 0)
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)

        var copiedAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &copiedAddress) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(socketFD, sockaddrPointer, &length)
            }
        }
        XCTAssertEqual(getsocknameResult, 0)

        let occupiedPort = Int(UInt16(bigEndian: copiedAddress.sin_port))
        let availablePort = PortScanner.firstAvailablePort(in: occupiedPort...(occupiedPort + 1))
        XCTAssertEqual(availablePort, occupiedPort + 1)
    }
}
