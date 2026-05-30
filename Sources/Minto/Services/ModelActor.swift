/// Custom global actor for STTService — serializes all whisper.cpp state access.
/// Using a global actor (not a regular actor) allows @ModelActor annotation on classes.
@globalActor
public actor ModelActor {
    public static let shared = ModelActor()
}
