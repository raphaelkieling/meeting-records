import Foundation

struct TranscriptionModel: Identifiable, Equatable, Sendable {
    struct Asset: Sendable {
        let path: String
        let bytes: Int64
        let tokenizer: Bool
    }

    static let revision = "0f63a7800b00dd0226abd051b906c246e1907482"
    let name: String
    let id: String
    let tokenizer: String
    let tokenizerRevision: String
    let files: [Asset]

    var downloadSize: Int64 { files.reduce(0) { $0 + $1.bytes } }
    var isNemotron: Bool { id == Self.nemotron.id }
    var version: String { isNemotron ? "transcribe.cpp-0.4.2:" + tokenizerRevision : Self.revision + ":" + tokenizerRevision }

    func url(for asset: Asset) -> URL {
        if isNemotron {
            return URL(string: "https://huggingface.co/\(tokenizer)/resolve/\(tokenizerRevision)/\(asset.path)")!
        }
        let repository = asset.tokenizer ? tokenizer : "argmaxinc/whisperkit-coreml"
        let revision = asset.tokenizer ? tokenizerRevision : Self.revision
        let path = asset.tokenizer ? asset.path : id + "/" + asset.path
        return URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")!
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    static let catalog = [large, small, base, nemotron]

    static let nemotron = TranscriptionModel(name: "Nemotron 3.5 ASR Streaming",
        id: "nemotron-3.5-asr-streaming-0.6b",
        tokenizer: "handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf",
        tokenizerRevision: "53ce288f69326b415aeef030cfcb02a08a8096dd",
        files: [.init(path: "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf", bytes: 751_094_240, tokenizer: false)])

    static let large = TranscriptionModel(name: "Whisper Large v3", id: "openai_whisper-large-v3-v20240930_626MB",
        tokenizer: "openai/whisper-large-v3", tokenizerRevision: "06f233fe06e710322aca913c1bc4249a0d71fce1", files: [
        .init(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/coremldata.bin", bytes: 348, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/metadata.json", bytes: 1922, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/model.mil", bytes: 934263, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/weights/weight.bin", bytes: 421968768, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/coremldata.bin", bytes: 329, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/metadata.json", bytes: 1850, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/model.mil", bytes: 10143, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/weights/weight.bin", bytes: 373376, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/coremldata.bin", bytes: 633, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/metadata.json", bytes: 4924, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/model.mil", bytes: 217177, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/weights/weight.bin", bytes: 203199860, tokenizer: false),
        .init(path: "config.json", bytes: 1149, tokenizer: false),
        .init(path: "generation_config.json", bytes: 2767, tokenizer: false),
        .init(path: "tokenizer.json", bytes: 2480617, tokenizer: true),
        .init(path: "tokenizer_config.json", bytes: 282843, tokenizer: true)
    ])

    static let small = TranscriptionModel(name: "Whisper Small", id: "openai_whisper-small",
        tokenizer: "openai/whisper-small", tokenizerRevision: "973afd24965f72e36ca33b3055d56a652f456b4d", files: [
        .init(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/coremldata.bin", bytes: 347, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/metadata.json", bytes: 1868, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/model.mil", bytes: 1636668, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/model.mlmodel", bytes: 155271, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/weights/weight.bin", bytes: 176323456, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/coremldata.bin", bytes: 328, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/metadata.json", bytes: 1848, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/model.mil", bytes: 10176, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/weights/weight.bin", bytes: 354080, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/coremldata.bin", bytes: 633, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/metadata.json", bytes: 4757, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/model.mil", bytes: 392094, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/model.mlmodel", bytes: 313629, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/weights/weight.bin", bytes: 307287346, tokenizer: false),
        .init(path: "config.json", bytes: 1456, tokenizer: false),
        .init(path: "generation_config.json", bytes: 2779, tokenizer: false),
        .init(path: "tokenizer.json", bytes: 2480466, tokenizer: true),
        .init(path: "tokenizer_config.json", bytes: 282683, tokenizer: true)
    ])

    static let base = TranscriptionModel(name: "Whisper Base", id: "openai_whisper-base",
        tokenizer: "openai/whisper-base", tokenizerRevision: "e37978b90ca9030d5170a5c07aadb050351a65bb", files: [
        .init(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/coremldata.bin", bytes: 347, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/metadata.json", bytes: 1863, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/model.mil", bytes: 579125, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/model.mlmodel", bytes: 79853, tokenizer: false),
        .init(path: "AudioEncoder.mlmodelc/weights/weight.bin", bytes: 41189632, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/coremldata.bin", bytes: 328, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/metadata.json", bytes: 1848, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/model.mil", bytes: 10176, tokenizer: false),
        .init(path: "MelSpectrogram.mlmodelc/weights/weight.bin", bytes: 354080, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/analytics/coremldata.bin", bytes: 243, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/coremldata.bin", bytes: 633, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/metadata.json", bytes: 4753, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/model.mil", bytes: 205217, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/model.mlmodel", bytes: 164481, tokenizer: false),
        .init(path: "TextDecoder.mlmodelc/weights/weight.bin", bytes: 104122162, tokenizer: false),
        .init(path: "config.json", bytes: 1464, tokenizer: false),
        .init(path: "generation_config.json", bytes: 2762, tokenizer: false),
        .init(path: "tokenizer.json", bytes: 2480466, tokenizer: true),
        .init(path: "tokenizer_config.json", bytes: 282683, tokenizer: true)
    ])
}
