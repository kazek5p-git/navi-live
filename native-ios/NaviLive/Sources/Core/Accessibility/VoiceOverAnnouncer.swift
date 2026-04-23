import AVFoundation
import UIKit

@MainActor
final class VoiceOverAnnouncer: NSObject {
  private let synthesizer = AVSpeechSynthesizer()
  private var navigationSpeechSessionActive = false

  override init() {
    super.init()
    synthesizer.delegate = self
  }

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

    speakWithSynthesizer(message, settings: settings, usesNavigationAudioSession: false)
  }

  func announceNavigation(_ message: String, settings: AppSettings) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    speakWithSynthesizer(message, settings: settings, usesNavigationAudioSession: true)
  }

  func stopSpeech() {
    synthesizer.stopSpeaking(at: .immediate)
    deactivateNavigationAudioSession()
  }

  private func speakWithSynthesizer(
    _ message: String,
    settings: AppSettings,
    usesNavigationAudioSession: Bool
  ) {
    if usesNavigationAudioSession {
      prepareNavigationAudioSession()
    }

    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = Float(max(0.35, min(settings.speechRate, 1.6)))
    utterance.volume = Float(max(0.1, min(settings.speechVolume, 1.0)))
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }

  private func prepareNavigationAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true)
      navigationSpeechSessionActive = true
    } catch {
      navigationSpeechSessionActive = false
    }
  }

  private func deactivateNavigationAudioSession() {
    guard navigationSpeechSessionActive else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Leave audio session as-is when deactivation fails.
    }
    navigationSpeechSessionActive = false
  }

  func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  func hapticWarning() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
  }
}

extension VoiceOverAnnouncer: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      deactivateNavigationAudioSession()
    }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor in
      deactivateNavigationAudioSession()
    }
  }
}
