import Foundation

/// 임베딩 인덱스 빌드 상태를 관리하는 ViewModel.
///
/// `MeetingLibraryView`에서 `Task.detached` 로 직접 관리하던
/// `embeddingIndex` / `embeddingBuildTask` / `rebuildEmbeddingIndex()` 를
/// 여기로 추출한다.
@MainActor
public final class SearchEmbeddingViewModel: ObservableObject {
    /// 백그라운드 빌드 완료 후 설치되는 임베딩 인덱스.
    /// nil이면 아직 빌드 중이거나 비활성 상태.
    @Published public private(set) var embeddingIndex: MeetingSearchEmbeddingIndex?

    private var embeddingBuildTask: Task<Void, Never>?

    public init() {}

    /// 검색 인덱스를 기반으로 임베딩 인덱스를 백그라운드에서 재빌드한다.
    ///
    /// 연속 호출 시 이전 Task를 취소해 stale 인덱스 설치를 막는다.
    public func rebuildEmbeddingIndex(from index: MeetingSearchIndex) {
        embeddingBuildTask?.cancel()
        embeddingIndex = nil
        embeddingBuildTask = Task.detached(priority: .background) { [weak self] in
            let built = try? await MeetingSearchEmbeddingBuilder(
                provider: LocalHashEmbeddingProvider()
            ).build(from: index)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.embeddingIndex = built
            }
        }
    }
}
