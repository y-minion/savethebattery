public enum SessionOutcome: String, Codable, Sendable { case running, succeeded, failed, cancelled, detached, expired }
public enum CleanupPolicy: String, Codable { case observe, safe }
public enum SessionPolicy {
    public static func cleanupAllowed(outcome: SessionOutcome, registered: Bool, shared: Bool, policy: CleanupPolicy) -> Bool { outcome == .succeeded && registered && !shared && policy == .safe }
}
