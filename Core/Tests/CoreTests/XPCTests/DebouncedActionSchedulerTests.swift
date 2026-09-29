import Core
import Testing

@ConverterEngineActor
@Test func debouncedActionRunsOnlyAfterLatestSchedule() {
    var scheduledActions: [@ConverterEngineActor @Sendable () -> Void] = []
    let scheduler = DebouncedActionScheduler { _, action in
        scheduledActions.append(action)
    }
    var executionCount = 0

    scheduler.schedule(after: 1) {
        executionCount += 1
    }
    scheduler.postponeIfScheduled(after: 1)

    #expect(scheduledActions.count == 2)
    scheduledActions[0]()
    #expect(executionCount == 0)
    #expect(scheduler.isPending)

    scheduledActions[1]()
    #expect(executionCount == 1)
    #expect(!scheduler.isPending)
}

@ConverterEngineActor
@Test func cancelledDebouncedActionDoesNotRun() {
    var scheduledAction: (@ConverterEngineActor @Sendable () -> Void)?
    let scheduler = DebouncedActionScheduler { _, action in
        scheduledAction = action
    }
    var didRun = false

    scheduler.schedule(after: 1) {
        didRun = true
    }
    scheduler.cancel()
    scheduledAction?()

    #expect(!didRun)
    #expect(!scheduler.isPending)
}
