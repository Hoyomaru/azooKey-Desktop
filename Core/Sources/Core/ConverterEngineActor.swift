#if os(Windows)
@globalActor
public actor ConverterEngineActor {
    public static let shared = ConverterEngineActor()
}
#else
public typealias ConverterEngineActor = MainActor
#endif
