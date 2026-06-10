import SwiftUI

// MARK: - SpeechEngineDisplayable

/// UI 전용 표현(아이콘·색·배지)을 단일 인터페이스로 제공한다.
/// SpeechEngineFamily와 SpeechEngineID 양쪽에 적용해
/// SettingsView의 12중복 함수를 6개로 줄인다.
protocol SpeechEngineDisplayable {
    var iconName: String { get }
    var tint: Color { get }
    var badgeLabel: String { get }
}

// MARK: - SpeechEngineID conformance
// UI 표현(extension)을 Model 파일이 아닌 UI 레이어 파일에 격리한다. 모듈 분리 시 이 extension은 UI 모듈에 남아야 한다.

extension SpeechEngineID: SpeechEngineDisplayable {
    var iconName: String {
        switch self {
        case .whisperAccurate:   return "checkmark.seal.fill"
        case .whisperBalanced:   return "slider.horizontal.3"
        case .whisperFast:       return "bolt.fill"
        case .speechAnalyzer:    return "sparkles"
        case .sfSpeechOnDevice:  return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .whisperAccurate:   return .green
        case .whisperBalanced:   return .blue
        case .whisperFast:       return .orange
        case .speechAnalyzer:    return .indigo
        case .sfSpeechOnDevice:  return .teal
        }
    }

    var badgeLabel: String { choiceBadge }
}

// MARK: - SpeechEngineFamily conformance
// UI 표현(extension)을 Model 파일이 아닌 UI 레이어 파일에 격리한다. 모듈 분리 시 이 extension은 UI 모듈에 남아야 한다.

extension SpeechEngineFamily: SpeechEngineDisplayable {
    var iconName: String {
        switch self {
        case .localAI:           return "checkmark.seal.fill"
        case .speechAnalyzer:    return "sparkles"
        case .sfSpeechOnDevice:  return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .localAI:           return .green
        case .speechAnalyzer:    return .indigo
        case .sfSpeechOnDevice:  return .teal
        }
    }

    var badgeLabel: String { choiceBadge }
}

