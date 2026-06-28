import Foundation

public enum MeetingSummarySchema {
    public static let schema = LLMJSONSchema(
        name: "meeting_summary",
        strict: true,
        schema: objectSchema(
            properties: [
                "title": stringSchema,
                "leadQuestion": stringSchema,
                "leadAnswer": stringSchema,
                "decisions": arraySchema(items: timedTextSchema),
                "actionItems": arraySchema(items: actionItemSchema),
                "openQuestions": arraySchema(items: timedTextSchema),
                "sections": arraySchema(items: sectionSchema),
                "keywords": arraySchema(items: stringSchema)
            ],
            required: [
                "title",
                "leadQuestion",
                "leadAnswer",
                "decisions",
                "actionItems",
                "openQuestions",
                "sections",
                "keywords"
            ]
        )
    )

    private static let actionItemSchema: LLMJSONValue = objectSchema(
        properties: [
            "task": stringSchema,
            "owner": stringSchema,
            "due": stringSchema,
            "time": stringSchema
        ],
        required: ["task", "owner", "due", "time"]
    )

    private static let pointSchema: LLMJSONValue = objectSchema(
        properties: [
            "text": stringSchema,
            "subPoints": arraySchema(items: stringSchema)
        ],
        required: ["text", "subPoints"]
    )

    private static let sectionSchema: LLMJSONValue = objectSchema(
        properties: [
            "title": stringSchema,
            "time": stringSchema,
            "points": arraySchema(items: pointSchema)
        ],
        required: ["title", "time", "points"]
    )

    private static let timedTextSchema: LLMJSONValue = objectSchema(
        properties: [
            "text": stringSchema,
            "time": stringSchema
        ],
        required: ["text", "time"]
    )

    private static let stringSchema: LLMJSONValue = .object(["type": .string("string")])

    private static func arraySchema(items: LLMJSONValue) -> LLMJSONValue {
        .object([
            "type": .string("array"),
            "items": items
        ])
    }

    private static func objectSchema(
        properties: [String: LLMJSONValue],
        required: [String]
    ) -> LLMJSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(LLMJSONValue.string)),
            "additionalProperties": .bool(false)
        ])
    }
}
