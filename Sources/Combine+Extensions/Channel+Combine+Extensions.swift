//
//  Channel+Combine+Extensions.swift
//  SwiftPhoenixClient
//
//  Created by Sudo.park on 2020/07/19.
//

import Foundation
import Combine


// MARK: - Channel Event Subscription

@available(iOS 13.0, *)
class ChannelEventSubscription<S: Subscriber>: Subscription, DemandBasePublishing where S.Input == Message, S.Failure == Never {
    
    private weak var channel: Channel?
    private var subscriber: S!
    private let event: String
    var publishedElementCount: Int = 0
    var currentDemand: Subscribers.Demand!
    private let lock = NSRecursiveLock()
    
    init(channel: Channel, event: String, subscriber: S) {
        self.channel = channel
        self.event = event
        self.subscriber = subscriber
        
        self.listenChannelEvents()
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
    
    private func listenChannelEvents() {
        channel?.on(self.event) { [weak self] message in
            guard let self = self, let subscriber = self.subscriber else { return }
            self.publishElementOrNot(subscriber, element: message)
        }
    }
}


// MARK: Channel Event Publsiher

@available(iOS 13.0, *)
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
        
        let subscription = ChannelEventSubscription(channel: self.channel, event: self.event, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }
}

// MARK: - Channel Publishers(wrap channel)

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


// MARK: - Channel event combine extensiosns

@available(iOS 13.0, *)
extension ChannelPublishers {
    
    public var onClose: AnyPublisher<Message, Never> {
        return ChannelEventPublisher(channel: self.channel, event: ChannelEvent.close)
            .eraseToAnyPublisher()
    }
    
    public var onError: AnyPublisher<Message, Never> {
        return ChannelEventPublisher(channel: self.channel, event: ChannelEvent.error)
            .eraseToAnyPublisher()
    }
    
    public func on(event: String) -> AnyPublisher<Message, Never> {
        return ChannelEventPublisher(channel: self.channel, event: event)
            .eraseToAnyPublisher()
    }
}



// MARK: - Channel Push


// MARK: - Push error

public enum PushError: Error {
    case fail(_ message: Message)
    case timeout(_ message: Message)
    
    public var payload: Payload {
        switch self {
        case let .fail(message),
             let .timeout(message):
            return message.payload
        }
    }
}


// MARK: - Push result subscription

@available(iOS 13.0, *)
class PushResultSubscribtion<S: Subscriber>: Subscription where S.Input == Message, S.Failure == Error {
    
    private weak var push: Push?
    private var subscriber: S!
    
    init(push: Push, subscriber: S) {
        self.push = push
        self.subscriber = subscriber
    }
    
    func request(_ demand: Subscribers.Demand) {
        self.listenResult()
    }
    
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

// MARK: - Push(+join, leave) result combine extensions

@available(iOS 13.0, *)
extension Push: Publisher {
    
    public typealias Output = Message
    public typealias Failure = Error
    
    public func receive<S>(subscriber: S) where S : Subscriber, Push.Failure == S.Failure, Push.Output == S.Input {
        let subscribtion = PushResultSubscribtion(push: self, subscriber: subscriber)
        subscriber.receive(subscription: subscribtion)
    }
}
