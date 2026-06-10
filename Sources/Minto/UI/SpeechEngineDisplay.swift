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

// MARK: - Shared view helpers (SettingsView 전용)

extension SettingsView {

    func engineIcon(for item: some SpeechEngineDisplayable) -> some View {
        Image(systemName: item.iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(item.tint)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.tint.opacity(0.12))
            )
    }

    func choiceBadge(for item: some SpeechEngineDisplayable) -> some View {
        Text(item.badgeLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(item.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(item.tint.opacity(0.12))
            )
    }

    func selectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    func selectionBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
    }
}
