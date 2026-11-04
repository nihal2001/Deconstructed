import AuthenticationServices
import CryptoKit
import SwiftUI

/// Asks Apple to confirm the signed-in person, for the code that lets the server revoke their
/// token. Cancelling throws `CancellationError`, so nothing else happens.
@MainActor
final class AppleConfirmation: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    static func authorizationCode() async throws -> String {
        let confirmation = AppleConfirmation()
        return try await withCheckedThrowingContinuation { continuation in
            confirmation.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
            controller.delegate = confirmation
            controller.presentationContextProvider = confirmation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8) else {
            continuation?.resume(throwing: BackendError.other("Apple didn't confirm this account. Nothing was deleted. Try again."))
            continuation = nil
            return
        }
        continuation?.resume(returning: code)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        continuation?.resume(throwing: cancelled ? CancellationError() : BackendError.other("Apple didn't confirm this account. Nothing was deleted. Try again."))
        continuation = nil
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deconstructed")
                            .font(.display(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("Restaurant scores you can explain. Pick a rubric, score each part, and the total takes care of itself.")
                            .font(.title3)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .hero(padding: 24)
                    .padding(.top, 28)

                    sample

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    if model.isDemo {
                        demoEntry
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            nonce = Self.randomNonce()
                            request.requestedScopes = [.fullName]
                            request.nonce = Self.sha256(nonce)
                        } onCompletion: { result in
                            handle(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(Capsule())
                        .disabled(isWorking)
                    }
                }
                .padding(24)
            }
        }
    }

    /// A static example of the idea, drawn with the same components as real scores.
    private var sample: some View {
        let version = StarterSystems.catalog.versions.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("How a score is built").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            if let version {
                let scores = DemoSeed.scoreMap(version, [4, 2, 1, 1])
                HStack(spacing: 14) {
                    ScoreRing(version: version, scores: scores, total: 8, diameter: 92)
                    ScoreBadge(total: 8, systemName: "General", size: .large)
                }
                ScoreBar(version: version, scores: scores, height: 16)
                BreakdownList(version: version, scores: scores, showsDescriptions: false)
            }
        }
        .card()
    }

    private var demoEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                DemoBadge()
                Text("This build has no Google or Supabase credentials, so it runs a self-contained demo. Every restaurant and person in it is invented, and nothing leaves this device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                #if DEBUG
                if !model.environment.config.missingCredentials.isEmpty {
                    Text("Missing: " + model.environment.config.missingCredentials.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.inkSoft)
                }
                #endif
            }
            Button {
                isWorking = true
                Task {
                    defer { isWorking = false }
                    do { try await model.signInDemo() } catch { errorMessage = error.localizedDescription }
                }
            } label: {
                Text("Explore the demo")
            }
            .buttonStyle(.primary)
            .disabled(isWorking)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // Cancelling the sheet is not an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in with Apple didn't complete. \(error.localizedDescription)"
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple didn't return an identity token. Please try again."
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await model.signInWithApple(idToken: token, nonce: nonce, displayName: name)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
