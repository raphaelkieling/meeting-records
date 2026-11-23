# Research: Local Multilingual Transcription

**Feature**: [Live Audio Transcription](spec.md)  
**Reference machine**: Apple M4 Max, 14 CPU cores, 36 GB unified memory, macOS 27.2.1.  
**Project compatibility floor**: macOS 14 in `Package.swift`.

## Decision: Select the model through a quality-first local benchmark

Do not claim a universally best model from public leaderboards. Benchmark the strongest practical candidates on the reference Mac and choose one production model. Rank transcript quality first across Brazilian Portuguese, Spanish, English, and language switching inside a recording. A candidate is eligible only if it meets the local, offline, durability, and responsiveness constraints in this plan.

The benchmark set must use consented real meeting audio with corrected reference transcripts. Keep those recordings outside the repository. Include both Me and Other tracks, overlap, quiet speech, background noise, and language changes. Give Brazilian Portuguese, Spanish, English, and mixed-language clips equal weight when calculating transcript quality. Record word error rate by language, character error rate, language identification, correction effort, timestamps, load and peak memory, processing time, backlog growth, and capture overruns. Vendor-published metrics inform which models to compare, but do not decide the winner.

### Candidates

| Candidate | Why evaluate it | Constraint to verify |
|---|---|---|
| **Qwen3-ASR-1.7B** | Strong quality-first challenger. The official project lists Portuguese, Spanish, and English, language identification, and reports its 1.7B model as its strongest open model. | The official streaming backend is vLLM-only and its streaming output has no timestamps. Confirm an offline Apple Silicon runtime and timestamp strategy before considering it for the app. |
| **Whisper large-v3 through WhisperKit** | Best Swift-native baseline found. WhisperKit supplies a Core ML based Swift runtime and an actor for streaming transcription; Argmax recommends `large-v3-v20240930_626MB` for maximum multilingual accuracy. Its current package manifest targets macOS 13, so it is compatible with this app's macOS 14 floor. | Benchmark the quality and memory of the available full and compressed assets, and verify the exact pinned version builds in the app. |

The Qwen repository reports lower WER than Whisper large-v3 on several of its multilingual benchmark sets, and higher average language-identification accuracy. These are publisher-run comparisons, so the project benchmark remains the decision gate. Qwen's streaming constraints matter for this app's source attribution and live updates. [Qwen3-ASR official repository](https://github.com/QwenLM/Qwen3-ASR), [Qwen3-ASR streaming implementation](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)

WhisperKit exposes streaming through `AudioStreamTranscriber` and supports local model selection and Core ML execution. Its model list marks large-v3 as multilingual and recommends a compressed large-v3 asset when multilingual accuracy is the priority. The current package manifest targets macOS 13, which fits the app's macOS 14 floor. [Argmax Swift SDK / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), [WhisperKit streaming actor](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift), [WhisperKit model definitions](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Models.swift), [WhisperKit package manifest](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Package.swift)

### Alternatives considered

- **NVIDIA Parakeet TDT v3 through Apple's Core AI model utilities**: an attractive local streaming experiment with Portuguese, Spanish, and English support. Apple's utilities currently target macOS 27+, while this app declares macOS 14. Do not raise the app's minimum OS solely for this feature; revisit only if the compatibility constraint changes. [Apple coreai-models Parakeet guide](https://github.com/apple/coreai-models/blob/main/models/parakeet/README.md), [Apple coreai-models platform requirement](https://github.com/apple/coreai-models)
- **Choose by vendor leaderboard alone**: rejected because the user's speech, language switching, two-track audio, and Apple Silicon workload may rank models differently.
- **Optimize for the shortest latency**: rejected because the user explicitly prioritizes recognition quality. Latency still must not compromise capture or app responsiveness.

## Decision: Separate capture, durable storage, and inference work

Keep the current capture callback and durable-write path highest priority. The repo already uses a dedicated serial `DispatchQueue` for AV capture, a bounded `AsyncThrowingStream` with capacity 64, an actor for `RecordingStorage`, and a `@MainActor` `RecordingCoordinator`. Extend this separation instead of doing inference in the capture queue, storage actor, or main actor.

After a persisted audio checkpoint is published, enqueue a reference to that durable segment for transcription. Use a bounded, ordered work queue per Input and source track. If inference falls behind, keep pending work on disk and report its backlog; never drop captured audio or create an unbounded task per chunk. Start with one loaded model instance and a bounded worker. Change concurrency only after profiling shows it helps without starving capture, increasing memory pressure, or duplicating work.

Use Swift Concurrency and actors for ownership and coordination; keep the existing serial DispatchQueue where the AV callback requires ordered delivery. Avoid manually creating a thread per task. Keep synchronous model inference away from `MainActor`; use a background async/nonisolated worker or a dedicated executor/queue if the model runtime blocks. Publish small progress updates to the UI and persist final transcript segments before advancing the durable checkpoint.

Apple recommends keeping non-UI work off the main actor, profiling before adding concurrency, choosing task granularity and QoS, and using Swift Concurrency or Dispatch to schedule work across cores. AVFoundation delivers capture buffers on the configured callback queue. Core ML exposes CPU/GPU/Neural Engine compute choices; select and tune them from measurements rather than forcing a device without evidence. [Apple: Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [Apple: Scheduling CPU work efficiently](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently), [Apple: audio sample-buffer delegate queue](https://developer.apple.com/documentation/avfoundation/avcaptureaudiodataoutput/setsamplebufferdelegate%28_%3Aqueue%3A%29), [Apple: Core ML compute units](https://developer.apple.com/documentation/coreml/mlmodelconfiguration)

## Decision: Preserve results per Input and derive the Meeting view

Persist each Input's status and timestamped transcript segments separately. Rebuild the Meeting's unified view in existing Input order, then by segment offset and source within each Input. Keep Me and Other source identity and overlapping timestamps. Replace the latest provisional segment when the model revises it; do not duplicate words when a chunk is finalized. The combined view is derived, not a second independently edited transcript.

On relaunch, mark unfinished transcription Pending and resume from the last durable checkpoint. Do not restart audio capture. Each new recording still begins only after an explicit user action and is a separate Input.

## Performance validation decisions

- Profile release builds on the reference M4 Max with Time Profiler and Swift Concurrency Instruments. Record model warm-up separately from steady-state inference.
- Run 60-minute dual-track capture with transcription enabled. The pass condition is zero audio loss or capture-overrun errors and usable Meeting navigation; measure update delay and backlog rather than imposing an unsupported sub-second target.
- After stopping, record how quickly pending segments drain. Include a run with the model deliberately slowed or temporarily unavailable to prove that capture remains durable and the pending queue stays bounded in memory.
- Repeat the model evaluation after selecting an asset and compute configuration. Keep test recordings local and record only anonymized metrics and corrected text scores in project artifacts.
