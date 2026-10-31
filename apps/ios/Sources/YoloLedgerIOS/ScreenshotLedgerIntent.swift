import AppIntents
import Foundation
import UniformTypeIdentifiers
import Vision
import YoloLedgerCore

struct ScreenshotLedgerIntent: AppIntent {
    static let title: LocalizedStringResource = "截图记账"
    static let description = IntentDescription("识别支付截图中的金额、商户和时间，并在有落中确认后记账。图片只在设备上处理。")
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "支付截图",
        description: "从“截屏”或“选择照片”操作传入的图片",
        supportedTypeIdentifiers: ["public.image"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("从 \(\.$screenshot) 识别并确认记账")
    }

    func perform() async throws -> some IntentResult {
        guard screenshot.data.count <= 40 * 1_024 * 1_024 else {
            throw ScreenshotLedgerIntentError.imageTooLarge
        }
        let proposal = try await ScreenshotTextRecognizer.recognize(imageData: screenshot.data)
        try await ScreenshotImportStore.save(proposal)
        return .result()
    }
}

struct YoloLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScreenshotLedgerIntent(),
            phrases: [
                "用 \(.applicationName) 截图记账",
                "\(.applicationName) 识别支付截图",
                "\(.applicationName) 轻点截图记账",
            ],
            shortTitle: "截图记账",
            systemImageName: "doc.text.viewfinder"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .lightBlue }
}

private enum ScreenshotTextRecognizer {
    static func recognize(imageData: Data) async throws -> LedgerScreenshotProposal {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.009

            let handler = VNImageRequestHandler(data: imageData)
            do {
                try handler.perform([request])
            } catch {
                throw ScreenshotLedgerIntentError.unreadableImage
            }

            let lines = (request.results ?? [])
                .sorted { left, right in
                    if abs(left.boundingBox.maxY - right.boundingBox.maxY) > 0.01 {
                        return left.boundingBox.maxY > right.boundingBox.maxY
                    }
                    return left.boundingBox.minX < right.boundingBox.minX
                }
                .compactMap { observation -> LedgerRecognizedTextLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return LedgerRecognizedTextLine(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        height: observation.boundingBox.height
                    )
                }
            guard !lines.isEmpty else { throw ScreenshotLedgerIntentError.noText }
            return LedgerScreenshotParser.parse(lines: lines)
        }.value
    }
}

enum ScreenshotImportStore {
    private static let pendingKey = "pending-screenshot-entry-v1"
    static let pendingDidChange = Notification.Name("YoloLedgerPendingScreenshotDidChange")

    @MainActor
    static func save(_ proposal: LedgerScreenshotProposal) throws {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(proposal), forKey: pendingKey)
            NotificationCenter.default.post(name: pendingDidChange, object: nil)
        } catch {
            throw ScreenshotLedgerIntentError.cannotPrepareConfirmation
        }
    }

    static func load() -> LedgerScreenshotProposal? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-screenshot-proposal") {
            return LedgerScreenshotProposal(
                amountMinorUnits: 5_500,
                merchant: "星巴克咖啡",
                transactionDate: Date(),
                kind: .expense,
                suggestedCategoryName: "餐饮",
                recognizedText: "支付成功\n星巴克咖啡\n实付 ¥55.00",
                confidence: .high
            )
        }
        #endif
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(LedgerScreenshotProposal.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}

private enum ScreenshotLedgerIntentError: LocalizedError {
    case imageTooLarge
    case unreadableImage
    case noText
    case cannotPrepareConfirmation

    var errorDescription: String? {
        switch self {
        case .imageTooLarge: "截图文件过大，请先裁剪后重试。"
        case .unreadableImage: "无法读取这张截图，请换一张清晰图片。"
        case .noText: "截图中没有识别到文字。"
        case .cannotPrepareConfirmation: "识别结果暂时无法交给有落，请重试。"
        }
    }
}
