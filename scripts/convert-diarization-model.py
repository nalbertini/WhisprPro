#!/usr/bin/env python3
"""
Convert pyannote speaker embedding model to Core ML via ONNX.
Usage: python3 scripts/convert-diarization-model.py
"""

import os
import sys
import torch
import torch.nn as nn
import numpy as np
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_DIR / "WhisprPro" / "Resources" / "SpeakerEmbedding.mlpackage"
ONNX_PATH = PROJECT_DIR / "scripts" / "speaker_embedding.onnx"

SAMPLE_RATE = 16000
WINDOW_SECONDS = 3
WINDOW_SAMPLES = SAMPLE_RATE * WINDOW_SECONDS

print("=== Speaker Embedding Model Converter ===")

# Step 1: Load model and extract core network
print("[1/5] Loading pyannote model...")
from pyannote.audio import Model
model = Model.from_pretrained("pyannote/wespeaker-voxceleb-resnet34-LM")
model.eval()

# Extract the core model without Lightning wrapper
# The underlying model is accessible and callable
print(f"  Model type: {type(model).__name__}")

# Create a simple wrapper that only does forward pass
class PureEmbeddingModel(nn.Module):
    def __init__(self, pyannote_model):
        super().__init__()
        # Copy all child modules from the pyannote model
        for name, module in pyannote_model.named_children():
            setattr(self, name, module)
        self._pyannote = pyannote_model

    def forward(self, x):
        # Use the pyannote model's forward logic but without Lightning
        with torch.no_grad():
            return self._pyannote(x)

pure_model = PureEmbeddingModel(model)
pure_model.eval()

# Step 2: Test forward pass
print("[2/5] Testing forward pass...")
sample_input = torch.randn(1, 1, WINDOW_SAMPLES)
with torch.no_grad():
    output = model(sample_input)
print(f"  Input shape: {sample_input.shape}")
print(f"  Output shape: {output.shape}")
embedding_dim = output.shape[-1]
print(f"  Embedding dim: {embedding_dim}")

# Step 3: Export to ONNX
print("[3/5] Exporting to ONNX...")
os.makedirs(ONNX_PATH.parent, exist_ok=True)

# Monkey-patch to avoid Lightning trainer check
import types
model.trainer = None
# Override the property that raises
original_class = model.__class__
for attr_name in dir(original_class):
    try:
        prop = getattr(original_class, attr_name)
        if isinstance(prop, property):
            pass
    except:
        pass

# Use torch.onnx.export with the raw model's forward
class SimpleWrapper(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m
        # Copy parameters
        self._params = dict(m.named_parameters())
        self._buffers = dict(m.named_buffers())

    def forward(self, x):
        # Manually call through the model's layers
        return self.m(x)

# Try ONNX export
try:
    torch.onnx.export(
        model,
        sample_input,
        str(ONNX_PATH),
        input_names=["audio"],
        output_names=["embedding"],
        dynamic_axes=None,
        opset_version=13,
        do_constant_folding=True,
    )
    print(f"  ONNX saved: {ONNX_PATH}")
except Exception as e:
    print(f"  ONNX export failed: {e}")
    print("  Trying alternative approach with torch.export...")

    # Alternative: use torch.export for newer PyTorch
    try:
        exported = torch.export.export(model, (sample_input,))
        torch.onnx.export(
            exported.module(),
            sample_input,
            str(ONNX_PATH),
            input_names=["audio"],
            output_names=["embedding"],
            opset_version=13,
        )
        print(f"  ONNX saved via torch.export: {ONNX_PATH}")
    except Exception as e2:
        print(f"  torch.export also failed: {e2}")
        print("  Falling back to coremltools direct conversion...")

        # Last resort: use coremltools unified converter with torch model directly
        import coremltools as ct

        # Convert using the traced forward pass
        print("  Attempting ct.convert with torch.jit.trace workaround...")

        # Remove the trainer property entirely
        type(model).trainer = property(lambda self: None)

        traced = torch.jit.trace(model, sample_input)
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="audio", shape=(1, 1, WINDOW_SAMPLES))],
            outputs=[ct.TensorType(name="embedding")],
            minimum_deployment_target=ct.target.macOS14,
        )

        mlmodel.author = "WhisprPro (converted from pyannote)"
        mlmodel.short_description = f"Speaker embedding model ({embedding_dim}D)"

        os.makedirs(OUTPUT_DIR.parent, exist_ok=True)
        mlmodel.save(str(OUTPUT_DIR))

        total_size = sum(f.stat().st_size for f in OUTPUT_DIR.rglob("*") if f.is_file())
        print(f"\n=== Done! ===")
        print(f"Model: {OUTPUT_DIR}")
        print(f"Size: {total_size / 1024 / 1024:.1f} MB")
        sys.exit(0)

# Step 4: Convert ONNX to Core ML
print("[4/5] Converting ONNX to Core ML...")
import coremltools as ct

mlmodel = ct.converters.onnx.convert(
    str(ONNX_PATH),
    minimum_deployment_target=ct.target.macOS14,
)

# Rename inputs/outputs
spec = mlmodel.get_spec()
ct.utils.rename_feature(spec, spec.description.input[0].name, "audio")
ct.utils.rename_feature(spec, spec.description.output[0].name, "embedding")
mlmodel = ct.models.MLModel(spec)

mlmodel.author = "WhisprPro (converted from pyannote)"
mlmodel.short_description = f"Speaker embedding model ({embedding_dim}D)"
mlmodel.input_description["audio"] = f"Audio waveform ({WINDOW_SECONDS}s at {SAMPLE_RATE}Hz)"
mlmodel.output_description["embedding"] = f"Speaker embedding ({embedding_dim}D)"

# Step 5: Save
print(f"[5/5] Saving to {OUTPUT_DIR}...")
os.makedirs(OUTPUT_DIR.parent, exist_ok=True)
mlmodel.save(str(OUTPUT_DIR))

# Cleanup
os.remove(ONNX_PATH)

total_size = sum(f.stat().st_size for f in OUTPUT_DIR.rglob("*") if f.is_file())
print(f"\n=== Done! ===")
print(f"Model: {OUTPUT_DIR}")
print(f"Size: {total_size / 1024 / 1024:.1f} MB")
print(f"Embedding dim: {embedding_dim}")
