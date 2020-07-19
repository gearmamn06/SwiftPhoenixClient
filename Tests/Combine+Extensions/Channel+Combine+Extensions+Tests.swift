//
//  Channel+Combine+Extensions+Tests.swift
//  SwiftPhoenixClientTests
//
//  Created by Sudo.park on 2020/07/19.
//

import XCTest
import Combine

import Starscream
@testable import SwiftPhoenixClient


@available(iOS 13.0, *)
class ChannelCombineExtensionsTests: XCTestCase, PublisherWaitable {
    
    var cancellables: Set<AnyCancellable>!
    private var mockWebSocketClient: WebSocketClientMock!
    private var mockSocket: SocketMock!
    private var channel: Channel!
    
    let kDefaultRef = "1"
    let kDefaultTimeout: TimeInterval = 10.0
    
    override func setUp() {
        super.setUp()
        self.cancellables = []
        self.mockWebSocketClient = WebSocketClientMock()
        self.mockSocket = SocketMock(endPoint: "/socket", transport: { _ in self.mockWebSocketClient })
        self.mockSocket.timeout = kDefaultTimeout
        self.mockSocket.makeRefReturnValue = kDefaultRef
        self.channel = Channel(topic: "test", params: ["key": "value"], socket: self.mockSocket)
        self.mockSocket.channelParamsReturnValue = self.channel
    }
    
    override func tearDown() {
        self.cancellables = nil
        self.mockWebSocketClient = nil
        self.mockSocket = nil
        self.channel = nil
        super.tearDown()
    }
}



// MARK: - Test Channel input

@available(iOS 13.0, *)
extension ChannelCombineExtensionsTests {
    
    func testChannel_joinSuccess() {
        // given
        let expect = expectation(description: "join the channel")
        
        // when
        let result = self.waitResult(expect, source: self.channel.joinThen()) {
            self.channel.joinPush?.trigger("ok", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isSuccess, true)
    }
    
    func testChannel_notLeak() {
        // given
        weak var channel: Channel? = Channel(topic: "test", socket: self.mockSocket)
        
        // when
        channel?.publishers.on(event: "some")
            .sink(receiveValue: { _ in })
            .store(in: &self.cancellables)
        
        // then
        XCTAssertNil(channel)
    }
    
    func testChannel_joinError() {
        // given
        let expect = expectation(description: "join channel error")
        
        // when
        let result = self.waitResult(expect, source: self.channel.joinThen()) {
            self.channel.joinPush?.trigger("error", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isFail, true)
    }
    
    func testChannel_joinTimeoutError() {
        // given
        let expect = expectation(description: "join channel timeout error")
        
        // when
        let result = self.waitResult(expect, source: self.channel.joinThen()) {
            self.channel.joinPush?.trigger("timeout", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isTimeoutFail, true)
    }
    
    func testChannel_leaveSuccess() {
        // given
        let expect = expectation(description: "leave channel success")
        
        // when
        let result = self.waitResult(expect, source: self.channel.leaveThen()) { }
        
        // then
        XCTAssertEqual(result?.isSuccess, true)
    }
    
    func testChannel_sendPush() {
        // given
        let expect = expectation(description: "send push to channel")
        self.channel.joinedOnce = true
        
        // when
        let futurePush = self.channel.pushThen("test", payload: [:])
        let result = self.waitResult(expect, source: futurePush) {
            futurePush.push.trigger("ok", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isSuccess, true)
    }
    
    func testChannel_sendPushFail() {
        // given
        let expect = expectation(description: "send push to channel fail")
        self.channel.joinedOnce = true
        
        // when
        let futurePush = self.channel.pushThen("test", payload: [:])
        let result = self.waitResult(expect, source: futurePush) {
            futurePush.push.trigger("error", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isFail, true)
    }
    
    func testChannel_sendPushTimeout() {
        // given
        let expect = expectation(description: "send push to channel timeout")
        self.channel.joinedOnce = true
        
        // when
        let futurePush = self.channel.pushThen("test", payload: [:])
        let result = self.waitResult(expect, source: futurePush) {
            futurePush.push.trigger("timeout", payload: [:])
        }
        
        // then
        XCTAssertEqual(result?.isTimeoutFail, true)
    }
}


// MARK: - Test Channel Events

@available(iOS 13.0, *)
extension ChannelCombineExtensionsTests {
    
    func testChannel_onClose() {
        // given
        let expect = expectation(description: "channel subscribe close event")
        
        // when
        let closeCount = self.wait(expect, source: self.channel.publishers.onClose) {
            self.channel.leave()
        }.count
        
        // then
        XCTAssertEqual(closeCount, 1)
    }
    
    func testChannel_onError() {
        // given
        let expect = expectation(description: "channel subscribe error event")
        
        // when
        let errorCount = self.wait(expect, source: self.channel.publishers.onError) {
            self.channel.trigger(event: ChannelEvent.error)
        }.count
        
        // then
        XCTAssertEqual(errorCount, 1)
    }
    
    func testChannel_onCustomEvents() {
        // given
        let expect = expectation(description: "channel subscribe custom events")
        
        // when
        let events = self.wait(expect, source: self.channel.publishers.on(event: "event1")) {
            self.channel.trigger(event: "event")
            self.channel.trigger(event: "event1")
            self.channel.trigger(event: "event2")
        }
        
        // then
        XCTAssertEqual(events.count, 1)
    }
}


private extension Result where Success == Message, Failure == Error {
    
    var isSuccess: Bool {
        guard case .success = self else { return false }
        return true
    }
    
    var isFail: Bool {
        guard case let .failure(error) = self,
            let pushError = error as? PushError,
            case .fail = pushError else {
            return false
        }
        return true
    }
    
    var isTimeoutFail: Bool {
        guard case let .failure(error) = self,
            let pushError = error as? PushError,
            case .timeout = pushError else {
                return false
        }
        return true
    }
}
