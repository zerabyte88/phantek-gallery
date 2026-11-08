# Translation Models Directory

This directory stores quantized INT8 ONNX translation models and SentencePiece tokenizers for 100% offline, on-device translation in Phantek Gallery.

Supported bilingual model pairings:
- `marian_ja_en_int8.onnx` (~42MB) - Japanese to English
- `marian_zh_en_int8.onnx` (~39MB) - Chinese to English
- `marian_ko_en_int8.onnx` (~41MB) - Korean to English
- `spm_ja.model` (<1.5MB)
- `spm_zh.model` (<1.5MB)
- `spm_ko.model` (<1.5MB)

When physical `.onnx` weight binaries are not present, `OnnxTranslationEngine` safely falls back to its comprehensive built-in offline manga dialog & SFX dictionary to guarantee zero-crash execution.
