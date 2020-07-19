//
//  PublisherWaitable.swift
//  SwiftPhoenixClientTests
//
//  Created by Sudo.park on 2020/07/19.
//

import XCTest
import Combine

@testable import SwiftPhoenixClient

@available(iOS 13.0, *)
protocol PublisherWaitable: class {
    
    var cancellables: Set<AnyCancellable>! { get set }
}


@available(iOS 13.0, *)
extension PublisherWaitable where Self: XCTestCase {
    
    func wait<O, F: Error>(_ expect: XCTestExpectation,
                      source: AnyPublisher<O, F>,
                      timeout: TimeInterval = 0.001,
                      action: () -> Void) -> [O] {
        var outputs: [O] = []
        source
            .sink(receiveCompletion: { _ in },
                  receiveValue: { output in
                    outputs.append(output)
                    expect.fulfill()
            })
            .store(in: &self.cancellables)
        action()
        self.wait(for: [expect], timeout: timeout)
        return outputs
    }
    
    func waitResult(_ expect: XCTestExpectation,
                    source: FuturePush,
                    timeout: TimeInterval = 0.001,
                    action: () -> Void) -> Result<Message, Error>? {
        var result: Result<Message, Error>?
        source
            .sink(receiveCompletion: { complete in
                if case let .failure(error) = complete {
                    result = .failure(error)
                    expect.fulfill()
                }
            }, receiveValue: { message in
                result = .success(message)
                expect.fulfill()
            })
            .store(in: &self.cancellables)
        action()
        self.wait(for: [expect], timeout: timeout)
        return result
    }
}
