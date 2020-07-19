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
}


// MARK: - SocketEventSubecription

@available(iOS 13.0, *)
extension Publishers {
    
    class SocketEventSubscription<O, S: Subscriber>: Subscription where S.Input == O, S.Failure == Never {
        
        typealias Listening = (Socket, @escaping (O) -> Void) -> Void
        
        private weak var socket: Socket?
        private var subscriber: S?
        private let listening: Listening
        
        init(socket: Socket, listening: @escaping Listening, subscriber: S) {
            self.socket = socket
            self.listening = listening
            self.subscriber = subscriber
            
            self.listenSocketEvents()
        }
        
        func request(_ demand: Subscribers.Demand) { }
        
        func cancel() {
            subscriber = nil
        }
        
        private func listenSocketEvents() {
            guard let subscriber = self.subscriber, let socket = self.socket else { return }
            self.listening(socket) { output in
                _ = subscriber.receive(output)
            }
        }
    }
}


// MARK: - SocketStatusEventPublisher

@available(iOS 13.0, *)
extension Publishers {
    
    internal struct SocketStatusEventPublisher: Publisher {
        
        typealias Output = SocketStatusEvent
        typealias Failure = Never
        
        private let socket: Socket
        
        internal init(socket: Socket) {
            self.socket = socket
        }
        
        internal func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let listenStatusEvents: (Socket, @escaping (SocketStatusEvent) -> Void) -> Void = { socket, callback in
                socket.onOpen {
                    callback(.onOpen)
                }
                socket.onClose {
                    callback(.onClose)
                }
                socket.onError { error in
                    callback(.onError(error))
                }
            }
            let subscription = SocketEventSubscription(socket: socket, listening: listenStatusEvents, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
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
    
    internal var _socketEvents: Publishers.SocketStatusEventPublisher {
        return Publishers.SocketStatusEventPublisher(socket: self.socket)
    }
    
    public var statusEvents: AnyPublisher<SocketStatusEvent, Never> {
        return self._socketEvents
            .eraseToAnyPublisher()
    }
    
    public var onOpen: AnyPublisher<Void, Never> {
        return statusEvents
            .compactMap { event -> Void? in
                guard case .onOpen = event else { return nil }
                return ()
        }
        .eraseToAnyPublisher()
    }
    
    public var onClose: AnyPublisher<Void, Never> {
        return statusEvents
            .compactMap { event -> Void? in
                guard case .onClose = event else { return nil }
                return ()
        }
        .eraseToAnyPublisher()
    }
    
    public var onError: AnyPublisher<Error, Never> {
        return statusEvents
            .compactMap { event -> Error? in
                guard case let .onError(error) = event else { return nil }
                return error
        }
        .eraseToAnyPublisher()
    }
    
    public var onMessage: AnyPublisher<Message, Never> {
        return Publishers.SocketMessageEventPublisher(socket: self.socket)
            .eraseToAnyPublisher()
    }
}
