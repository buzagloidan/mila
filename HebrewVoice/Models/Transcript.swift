import Foundation

struct Transcript: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var duration: TimeInterval = 0
    var text = ""
    var audioFilename: String?
    var isComplete = false
    var sourceID: UUID?
}

enum VoiceError: LocalizedError {
    case modelMissing, engineFailed, microphoneDenied, invalidAudio, overloaded, cancelled

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "קובצי המודל חסרים. יש להתקין מחדש את האפליקציה."
        case .engineFailed: return "לא ניתן להפעיל את מנוע התמלול. נסו שוב."
        case .microphoneDenied: return "יש לאפשר גישה למיקרופון בהגדרות המכשיר כדי להקליט."
        case .invalidAudio: return "לא ניתן לקרוא שמע בקובץ הזה. בחרו קובץ שמע תקין."
        case .overloaded: return "התמלול לא הצליח לעמוד בקצב ההקלטה ונעצר. התמלול והשמע שכבר עובדו נשמרו."
        case .cancelled: return "התמלול בוטל. הטקסט שכבר תומלל נשמר."
        }
    }
}

extension TimeInterval {
    var clockText: String {
        let seconds = max(0, Int(self))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
