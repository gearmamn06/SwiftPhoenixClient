//
//  Channel+Combine+Extensions.swift
//  SwiftPhoenixClient
//
//  Created by Sudo.park on 2020/07/19.
//

import Foundation
import Combine



public struct ChannelPublishers {
    
    private let channel: Channel
    
    init(channel: Channel) {
        self.channel = channel
    }
}


@available(iOS 13.0, *)
extension Channel {
    
    public var publishers: ChannelPublishers {
        return ChannelPublishers(channel: self)
    }
}


@available(iOS 13.0, *)
extension Publishers {
    
    class ChannelEventSubscription<O, S: Subscriber>: Subscription where S.Input == O, S.Failure == Never {
        
        typealias Listening = (Channel, @escaping (O) -> Void) -> Void
        
        private weak var channel: Channel?
        private var subscriber: S!
        private let listening: Listening
        
        init(channel: Channel, listening: @escaping Listening, subscriber: S) {
            self.channel = channel
            self.listening = listening
            self.subscriber = subscriber
            
            self.listenChannelEvents()
        }
        
        func request(_ demand: Subscribers.Demand) { }
        
        func cancel() {
            self.subscriber = nil
        }
        
        private func listenChannelEvents() {
            guard let subscriber = self.subscriber, let channel = channel else { return }
            self.listening(channel) { output in
                _ = subscriber.receive(output)
            }
        }
    }
}


@available(iOS 13.0, *)
extension Publishers {
    
    struct ChannelEventPublisher: Publisher {
        
        typealias Output = Message
        typealias Failure = Never
        
        private let channel: Channel
        private let event: String
        
        init(channel: Channel, event: String) {
            self.channel = channel
            self.event = event
        }
        
        func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let event = self.event
            let listenEvents: (Channel, @escaping (Message) -> Void) -> Void = { channel, callback in
                channel.on(event) { message in
                    callback(message)
                }
            }
            
            let subscription = ChannelEventSubscription(channel: self.channel, listening: listenEvents, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }
}


@available(iOS 13.0, *)
extension ChannelPublishers {
    
    public var onClose: AnyPublisher<Message, Never> {
        return Publishers.ChannelEventPublisher(channel: self.channel, event: ChannelEvent.close)
            .eraseToAnyPublisher()
    }
    
    public var onError: AnyPublisher<Message, Never> {
        return Publishers.ChannelEventPublisher(channel: self.channel, event: ChannelEvent.error)
            .eraseToAnyPublisher()
    }
    
    public func on(event: String) -> AnyPublisher<Message, Never> {
        return Publishers.ChannelEventPublisher(channel: self.channel, event: event)
            .eraseToAnyPublisher()
    }
}


public enum PushError: Error {
    case fail(_ message: Message)
    case timeout(_ message: Message)
}


@available(iOS 13.0, *)
extension Publishers {
    
    class PushSubscribtion<S: Subscriber>: Subscription where S.Input == Message, S.Failure == Error {
        
        private weak var push: Push?
        private var subscriber: S!
        
        init(push: Push, subscriber: S) {
            self.push = push
            self.subscriber = subscriber
            self.listenResult()
        }
        
        func request(_ demand: Subscribers.Demand) { }
        
        func cancel() {
            subscriber = nil
        }
        
        private func listenResult() {
            guard let subscriber = self.subscriber, let push = self.push else { return }
            
            let onOk: (Message) -> Void = {
                _ = subscriber.receive($0)
                subscriber.receive(completion: .finished)
            }
            let onError: (Message) -> Void = {
                let error: PushError = .fail($0)
                subscriber.receive(completion: .failure(error))
            }
            let onTimeout: (Message) -> Void = {
                let error: PushError = .timeout($0)
                subscriber.receive(completion: .failure(error))
            }
            push
            .receive("ok", callback: onOk)
            .receive("error", callback: onError)
            .receive("timeout", callback: onTimeout)
        }
    }
}

@available(iOS 13.0, *)
struct FuturePush: Publisher {
    
    typealias Output = Message
    typealias Failure = Error
    
    let push: Push

    public init(push: Push) {
        self.push = push
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        let subscribtion = Publishers.PushSubscribtion(push: self.push, subscriber: subscriber)
        subscriber.receive(subscription: subscribtion)
    }
}



// MARK: - Extensions for channel input

@available(iOS 13.0, *)
public typealias SinglePublish = AnyPublisher

@available(iOS 13.0, *)
extension Channel {
    
    func joinThen(timeout: TimeInterval? = nil) -> FuturePush {
        return FuturePush(push: self.join(timeout: timeout))
    }
    
    public func joinAsSingle(timeout: TimeInterval? = nil) -> SinglePublish<Message, Error> {
        return joinThen(timeout: timeout)
            .eraseToAnyPublisher()
    }
    
    func leaveThen(timeout: TimeInterval = Defaults.timeoutInterval) -> FuturePush {
        return FuturePush(push: self.leave(timeout: timeout))
    }
    
    public func leaveAsSingle(timeout: TimeInterval = Defaults.timeoutInterval) -> SinglePublish<Message, Error> {
        return leaveThen(timeout: timeout)
            .eraseToAnyPublisher()
    }
    
    func pushThen(_ event: String,
                         payload: Payload,
                         timeout: TimeInterval = Defaults.timeoutInterval) -> FuturePush {
        return FuturePush(push: self.push(event, payload: payload, timeout: timeout))
    }
    
    public func pushAsSingle(_ event: String,
                                payload: Payload,
                                timeout: TimeInterval = Defaults.timeoutInterval) -> SinglePublish<Message, Error> {
        return self.pushThen(event, payload: payload, timeout: timeout)
            .eraseToAnyPublisher()
    }
}
