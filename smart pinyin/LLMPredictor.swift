//
//  LLMPredictor.swift
//  smart pinyin
//
//  Handles loading a small LLM via MLX and predicting next-token
//  probability distributions for text suggestions.
//

import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

// MARK: - Prediction Result

/// A single next-token prediction with its probability.
struct TokenPrediction: Sendable {
    /// The decoded text of the predicted token.
    let text: String
    /// Probability (0.0 ... 1.0) assigned by the model.
    let probability: Float
    /// Raw token ID.
    let tokenID: Int
}

// MARK: - Predictor State

enum PredictorState {
    case unloaded
    case loading(progress: Double)
    case loaded
    case error(String)
}

// MARK: - LLM Predictor

@MainActor
final class LLMPredictor {

    // MARK: State

    var state: PredictorState = .unloaded
    var predictions: [TokenPrediction] = []
    var modelName: String = ""

    // MARK: Private

    /// The model configuration – defaults to a small 4-bit Qwen2.5 0.5B
    /// which handles Chinese well. Swap to `smolLM_135M_4bit` for an even
    /// smaller (~80 MB) English-focused alternative.
    private var modelConfig = LLMRegistry.qwen205b4bit

    /// Number of top predictions to return.
    private let topK = 10

    /// Maximum number of recent characters to keep as context.
    /// Limits forward-pass cost for long documents.
    private let maxContextChars = 512

    private var modelContainer: ModelContainer?

    // MARK: Load

    func loadModel() async {
        guard case .unloaded = state else { return }

        state = .loading(progress: 0)
        modelName = modelConfig.name.components(separatedBy: "/").last ?? modelConfig.name

        Memory.cacheLimit = 20 * 1024 * 1024  // 20 MB buffer cache

        do {
            // Resolve & download model
            let downloader = #hubDownloader()
            let resolved = try await resolve(
                configuration: modelConfig,
                from: downloader,
                useLatest: false
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .loading(progress: progress.fractionCompleted)
                }
            }

            // Load model + tokenizer
            let container = try await LLMModelFactory.shared.loadContainer(
                from: resolved.modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )

            // Pre-allocate cache inside the model's context
            let numParams = await container.perform { $0.model.numParameters() }
            NSLog("📦 LLMPredictor: loaded \(numParams / 1_000_000)M parameters")

            self.modelContainer = container
            self.state = .loaded

        } catch {
            NSLog("❌ LLMPredictor load failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: Predict

    /// Given the current text context, return top-k next-token predictions
    /// together with their softmax probabilities.
    ///
    /// This runs a full forward pass each time. For input-method use the
    /// text is typically short enough that this is fast.
    func predict(nextTo text: String) async {
        guard case .loaded = state, let container = modelContainer else { return }

        let k = self.topK

        let result: [TokenPrediction] = await container.perform { context in

            // ---- tokenize (with context window truncation) ----
            let truncatedText = String(text.suffix(maxContextChars))
            let tokenIDs = context.tokenizer.encode(text: truncatedText)
            guard !tokenIDs.isEmpty else { return [] }

            let mlxTokens = MLXArray(tokenIDs)[.newAxis, 0...]
            let lmInput = LMInput.Text(tokens: mlxTokens)

            // ---- run model (full forward pass) ----
            let cache = context.model.newCache(parameters: nil)
            let output = context.model(lmInput, cache: cache, state: nil)

            // ---- extract logits for the last position ----
            var logits = output.logits
            if logits.dtype == .bfloat16 {
                logits = logits.asType(.float32)
            }
            let lastLogits = logits[0..., -1, 0...]

            // ---- softmax → probabilities ----
            let probs = MLX.softmax(lastLogits, axis: -1)

            // ---- top-k via argSort ----
            let sortedIndices = MLX.argSort(probs, axis: -1)
            let vocabSize = probs.dim(-1)
            let topK = min(k, vocabSize)

            let indicesArray = sortedIndices.asArray(Int32.self)
            let probsArray = probs.asArray(Float.self)

            var predictions: [TokenPrediction] = []
            for i in 0 ..< topK {
                let idx = Int(indicesArray[vocabSize - 1 - i])
                let prob = probsArray[idx]
                let tokenText = context.tokenizer.decode(tokenIds: [idx])
                let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Always include the token; skip empty strings
                if !trimmed.isEmpty {
                    predictions.append(TokenPrediction(
                        text: tokenText,
                        probability: prob,
                        tokenID: idx
                    ))
                }
            }
            return predictions
        }

        self.predictions = result
    }

    // MARK: Controls

    /// Reset internal state when the input context changes entirely.
    func resetContext() {
        predictions = []
    }

    /// Change the model configuration. Requires calling `loadModel()` afterward.
    func setModel(_ config: ModelConfiguration) {
        modelConfig = config
        resetContext()
        state = .unloaded
        modelContainer = nil
    }
}
