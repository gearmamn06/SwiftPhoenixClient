//
//  Socket+Combine+Extensions+Tests.swift
//  SwiftPhoenixClient
//
//  Created by Sudo.park on 2020/07/19.
//

import XCTest
import Combine

import Starscream
@testable import SwiftPhoenixClient


@available(iOS 13.0, *)
class SocketCombineExtensionsTests: XCTestCase {
    
    private var cancellables: Set<AnyCancellable>!
    private var mockWebSocket: WebSocketClientMock!
    private var mockSocketTransport: (((URL) -> WebSocketClient))!
    private var socket: Socket!
    
    private let timeout: TimeInterval = 0.001
    
    override func setUp() {
        super.setUp()
        self.cancellables = []
        self.mockWebSocket = WebSocketClientMock()
        self.mockSocketTransport = { _ in return self.mockWebSocket }
        self.socket = Socket(endPoint: "/socket", transport: self.mockSocketTransport)
    }
    
    override func tearDown() {
        self.cancellables = nil
        self.mockWebSocket = nil
        self.mockSocketTransport = nil
        self.socket = nil
        super.tearDown()
    }
    
    private func connectWebSocket() {
        self.mockWebSocket.isConnected = false
        self.socket.connect()
        self.mockWebSocket.delegate?.websocketDidConnect(socket: self.mockWebSocket)
    }
    
    private func disconnectWebSocket(withError error: Error? = nil) {
        self.mockWebSocket.delegate?.websocketDidDisconnect(socket: self.mockWebSocket, error: error)
    }
    
    private func publishMessage() {
        let data: [String: Any] = ["topic":"topic","event":"event","payload":["go": true],"status":"ok"]
        let text = toWebSocketText(data: data)
        mockWebSocket.delegate?.websocketDidReceiveMessage(socket: mockWebSocket, text: text)
    }
}


// MARK: - Test Socket event chaneged

@available(iOS 13.0, *)
extension SocketCombineExtensionsTests {
    
    func testSocket_publishSocketEvents() {
        // given
        let expect = expectation(description: "publish socket status events")
        expect.expectedFulfillmentCount = 4
        
        // when
        let events = self.wait(expect, source: self.socket.puboishers.statusEvents) {
            self.connectWebSocket()
            self.disconnectWebSocket()
            self.disconnectWebSocket(withError: TestError.stub)
        }
        
        // then
        let expectedEvents: [SocketStatusEvent] = [.onOpen, .onClose, .onClose, .onError(TestError.stub)]
        XCTAssertEqual(events.descriptions, expectedEvents.descriptions)
    }
    
    func testSocket_publishOpenEvent() {
        // given
        let expect = expectation(description: "publish socket open event")
        
        // when
        let openCount = self.wait(expect, source: self.socket.puboishers.onOpen) {
            self.connectWebSocket()
        }
        .count
        
        // then
        XCTAssertEqual(openCount, 1)
    }
    
    func testSocket_publishCloseEvent() {
        // given
        let expect = expectation(description: "publish socket open event")
        
        // when
        let closeCount = self.wait(expect, source: self.socket.puboishers.onClose) {
            self.connectWebSocket()
            self.disconnectWebSocket()
        }
        .count
        
        // then
        XCTAssertEqual(closeCount, 1)
    }
    
    func testSocket_publishErrorEvent() {
        // given
        let expect = expectation(description: "publish socket open event")
        
        // when
        let errors = self.wait(expect, source: self.socket.puboishers.onError) {
            self.connectWebSocket()
            self.disconnectWebSocket(withError: TestError.stub)
        }
        
        // then
        XCTAssertEqual(errors.count, 1)
    }
    
    func testSocket_publishMessageEvent() {
        // given
        let expect = expectation(description: "publish message events")
        
        // when
        let messages = self.wait(expect, source: self.socket.puboishers.onMessage) {
            self.connectWebSocket()
            self.publishMessage()
        }
        
        // then
        XCTAssertEqual(messages.count, 1)
    }
}


@available(iOS 13.0, *)
extension SocketCombineExtensionsTests {
    
    private func wait<Output>(_ expect: XCTestExpectation,
                              source: AnyPublisher<Output, Never>,
                              action: () -> Void) -> [Output] {
        var outputs = [Output]()
        source
            .sink(receiveValue: { output in
                outputs.append(output)
                expect.fulfill()
            })
            .store(in: &self.cancellables)
        action()
        self.wait(for: [expect], timeout: self.timeout)
        return outputs
    }
}


private extension SocketStatusEvent {
    
    var description: String {
        switch self {
        case .onOpen: return "onOpen"
        case .onClose: return "onClose"
        case let .onError(error): return "onError:\(error.localizedDescription)"
        }
    }
}

private extension Array where Element == SocketStatusEvent {
    
    var descriptions: [String] {
        return self.map{ $0.description }
    }
}
