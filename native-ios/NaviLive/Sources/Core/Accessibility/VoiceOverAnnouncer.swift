import AVFoundation
import UIKit

@MainActor
final class VoiceOverAnnouncer {
  private let synthesizer = AVSpeechSynthesizer()

  func announce(_ message: String, settings: AppSettings) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let shouldUseVoiceOver: Bool
    switch settings.speechMode {
    case .automatic:
      shouldUseVoiceOver = UIAccessibility.isVoiceOverRunning
    case .voiceOver:
      shouldUseVoiceOver = true
    case .speechSynthesizer:
      shouldUseVoiceOver = false
    }

    if shouldUseVoiceOver {
      UIAccessibility.post(notification: .announcement, argument: message)
      return
    }

    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = Float(max(0.35, min(settings.speechRate, 1.6)))
    utterance.volume = Float(max(0.1, min(settings.speechVolume, 1.0)))
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }

  func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  func hapticWarning() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
  }
}
