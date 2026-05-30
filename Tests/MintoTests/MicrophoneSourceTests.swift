import Testing
@testable import MintoCore
import Foundation

@Suite("MicrophoneSource Tests")
struct MicrophoneSourceTests {

    @Test("start() throws 없이 onError 콜백으로 에러 전달")
    func startDoesNotThrow() throws {
        let source = MicrophoneSource()
        nonisolated(unsafe) var receivedError: AudioSourceError?
        source.onError = { error in
            receivedError = error
        }

        // start()은 throw 없이 동작 — 권한 거부 시 onError(.permissionDenied) 호출
        #expect(throws: Never.self) {
            try source.start()
        }
        source.stop()
    }

    @Test("stop()은 시작 전에 호출해도 크래시하지 않음")
    func stopBeforeStartIsSafe() {
        let source = MicrophoneSource()
        source.stop()  // guard let engine else { return } 로 안전하게 처리
    }

    @Test("availableDevices는 [AudioDevice] 타입 반환")
    func availableDevicesReturnsCorrectType() {
        let source = MicrophoneSource()
        let devices = source.availableDevices
        // CI 환경에서는 빈 배열일 수 있지만 타입은 항상 [AudioDevice]
        for device in devices {
            #expect(!device.id.isEmpty)
            #expect(!device.name.isEmpty)
        }
    }

    @Test("onBuffer/onError 콜백 할당 후 해제 시 크래시 없음")
    func callbackAssignmentIsSafe() {
        let source = MicrophoneSource()
        source.onBuffer = { _ in }
        source.onError = { _ in }
        source.onBuffer = nil
        source.onError = nil
        // 크래시 없이 통과해야 함
    }

    @Test("AudioSourceProtocol 인터페이스 준수 검증")
    func conformsToAudioSourceProtocol() {
        let source: AudioSourceProtocol = MicrophoneSource()
        // 프로토콜 메서드가 존재하고 호출 가능한지 확인
        _ = source.availableDevices
        source.stop()
    }
}
