import Foundation

/// ConverterEngineActor 上の処理を、最後の操作から一定時間後まで遅延するためのスケジューラ。
///
/// ConverterServer のように入力処理と低優先度の同期処理が同じactorを使う場合に、
/// 入力が続いている間は同期処理をクリティカルパスへ入れないために使う。
public final class DebouncedActionScheduler {
    public typealias Action = @ConverterEngineActor @Sendable () -> Void
    public typealias Schedule = (TimeInterval, @escaping Action) -> Void

    private let schedule: Schedule
    private var generation: UInt64 = 0
    private var pendingAction: Action?

    public init(
        schedule: @escaping Schedule = { delay, action in
            Task { @ConverterEngineActor in
                let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                action()
            }
        }
    ) {
        self.schedule = schedule
    }

    @ConverterEngineActor public var isPending: Bool {
        pendingAction != nil
    }

    @ConverterEngineActor public func schedule(after delay: TimeInterval, action: @escaping Action) {
        pendingAction = action
        arm(after: delay)
    }

    @ConverterEngineActor public func postponeIfScheduled(after delay: TimeInterval) {
        guard pendingAction != nil else {
            return
        }
        arm(after: delay)
    }

    @ConverterEngineActor public func cancel() {
        generation &+= 1
        pendingAction = nil
    }

    @ConverterEngineActor private func arm(after delay: TimeInterval) {
        generation &+= 1
        let scheduledGeneration = generation
        schedule(delay) { [weak self] in
            guard let self,
                  self.generation == scheduledGeneration,
                  let action = self.pendingAction else {
                return
            }
            self.pendingAction = nil
            action()
        }
    }
}
