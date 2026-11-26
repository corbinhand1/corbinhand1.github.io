import LocalAuthentication

enum Biometrics {
    /// True when this device has Face ID / Touch ID set up.
    static var isAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    static var name: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    /// Asks for Face ID, falling back to the device passcode. Returns the
    /// authenticated context (reusable for a few seconds) or nil if cancelled/failed.
    static func authenticate(reason: String) async -> LAContext? {
        let ctx = LAContext()
        ctx.touchIDAuthenticationAllowableReuseDuration = 10
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? ctx : nil
        } catch { return nil }
    }
}
