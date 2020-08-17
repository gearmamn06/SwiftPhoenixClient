//
//  Socket+Combine+Extensions.swift
//  SwiftPhoenixClient
//
//  Created by Sudo.park on 2020/07/19.
//

import Foundation
import Combine



// MARK: SocketStatus Events

public enum SocketStatusEvent {
    case onOpen
    case onClose
    case onError(_ error: Error)
        
    
    enum EventType {
        case open
        case close
        case error
        case all
    }
}

@available(iOS 13.0, *)
protocol DemandBasePublishing: class {
    var publishedElementCount: Int { get set }
    var currentDemand: Subscribers.Demand! { get set }
}

@available(iOS 13.0, *)
extension DemandBasePublishing {
    
    private func shouldPublishElement() -> Bool {
        guard let currentDemand = self.currentDemand else { return false }
        guard let max = currentDemand.max else {
            return true
        }
        let remainCount = max - self.publishedElementCount
        return remainCount > 0
    }
    
    func publishElementOrNot<S: Subscriber>(_ subscriber: S, element: S.Input) {
        guard self.shouldPublishElement() else { return }
        let additionalDemand = subscriber.receive(element)
        self.publishedElementCount += 1
        self.currentDemand += additionalDemand
    }
}


// MARK: - SocketEventSubecription

@available(iOS 13.0, *)
class SocketEventSubscription<O, S: Subscriber>: Subscription, DemandBasePublishing where S.Input == O, S.Failure == Never {
    
    typealias Listening = (Socket, @escaping (O) -> Void) -> Void
    
    private weak var socket: Socket?
    private var subscriber: S?
    private let listening: Listening
    var publishedElementCount: Int = 0
    var currentDemand: Subscribers.Demand!
    private let lock = NSRecursiveLock()
    
    init(socket: Socket, listening: @escaping Listening, subscriber: S) {
        self.socket = socket
        self.listening = listening
        self.subscriber = subscriber
        
        self.listenSocketEvents()
    }
    
    func request(_ demand: Subscribers.Demand) {
        self.lock.lock()
        self.publishedElementCount = 0
        self.currentDemand = demand
        self.lock.unlock()
    }
    
    func cancel() {
        self.lock.lock()
        self.subscriber = nil
        self.lock.unlock()
    }
    
    private func listenSocketEvents() {
        guard let socket = self.socket else { return }
        self.listening(socket) { [weak self] output in
            guard let self = self, let subscriber = self.subscriber else { return }
            self.publishElementOrNot(subscriber, element: output)
        }
    }
}

// MARK: - SocketStatusEventPublisher

@available(iOS 13.0, *)
internal struct SocketStatusEventPublisher: Publisher {
    
    typealias Output = SocketStatusEvent
    typealias Failure = Never
    
    private let socket: Socket
    private let eventType: SocketStatusEvent.EventType
    
    internal init(socket: Socket, eventType: SocketStatusEvent.EventType) {
        self.socket = socket
        self.eventType = eventType
    }
    
    internal func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        
        let type = self.eventType
        let listenStatusEvents: (Socket, @escaping (SocketStatusEvent) -> Void) -> Void = { socket, callback in
            if type == .open || type == .all {
                socket.onOpen {
                    callback(.onOpen)
                }
            }
            if type == .close || type == .all {
                socket.onClose {
                    callback(.onClose)
                }
            }
            if type == .error || type == .all {
                socket.onError { error in
                    callback(.onError(error))
                }
            }
        }
        let subscription = SocketEventSubscription(socket: socket, listening: listenStatusEvents, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

// MARK: - SocketMessageEventPublisher

@available(iOS 13.0, *)
extension Publishers {

    internal struct SocketMessageEventPublisher: Publisher {
        
        internal typealias Output = Message
        internal typealias Failure = Never
        
        private let socket: Socket
        
        internal init(socket: Socket) {
            self.socket = socket
        }
        
        internal func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let listenMessageEvents: (Socket, @escaping (Message) -> Void) -> Void = { socket, callback in
                socket.onMessage { message in
                    callback(message)
                }
            }
            
            let subscription = SocketEventSubscription(socket: socket, listening: listenMessageEvents, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
}



// MARK: - Socket Publishers(wrap socket)

public struct SocketPublishers {
    
    internal let socket: Socket
}

@available(iOS 13.0, *)
extension Socket {
    
    public var puboishers: SocketPublishers {
        return SocketPublishers(socket: self)
    }
}


// MARK: - Socket Comnine Extensions

@available(iOS 13.0, *)
extension SocketPublishers {
    
    private func socketEventPublsidher(for type: SocketStatusEvent.EventType) -> SocketStatusEventPublisher {
        return SocketStatusEventPublisher(socket: self.socket, eventType: type)
    }
    
    public var statusEvents: AnyPublisher<SocketStatusEvent, Never> {
        return self.socketEventPublsidher(for: .all)
            .eraseToAnyPublisher()
    }
    
    public var onOpen: AnyPublisher<Void, Never> {
        return self.socketEventPublsidher(for: .open)
            .map{ _ in }
            .eraseToAnyPublisher()
    }
    
    public var onClose: AnyPublisher<Void, Never> {
        return self.socketEventPublsidher(for: .close)
            .map{ _ in }
            .eraseToAnyPublisher()
    }
    
    public var onError: AnyPublisher<Error, Never> {
        return self.socketEventPublsidher(for: .error)
            .compactMap { status -> Error? in
                guard case let .onError(error) = status else { return nil }
                return error
            }
            .eraseToAnyPublisher()
    }
    
    public var onMessage: AnyPublisher<Message, Never> {
        return Publishers.SocketMessageEventPublisher(socket: self.socket)
            .eraseToAnyPublisher()
    }
}
