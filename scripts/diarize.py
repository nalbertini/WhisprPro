#!/usr/bin/env python3
"""
Speaker diarization script using pyannote.audio.
Called by WhisprPro as a subprocess.

Usage: python3 diarize.py <audio_file> [--num-speakers N]
Output: JSON to stdout with speaker segments

Example output:
{"speakers": [
  {"start": 0.0, "end": 2.5, "speaker": 0},
  {"start": 2.5, "end": 5.1, "speaker": 1},
  ...
]}
"""

import sys
import json
import argparse
import warnings
warnings.filterwarnings("ignore")

def main():
    parser = argparse.ArgumentParser(description="Speaker diarization")
    parser.add_argument("audio_file", help="Path to audio file")
    parser.add_argument("--num-speakers", type=int, default=0, help="Number of speakers (0=auto)")
    parser.add_argument("--min-speakers", type=int, default=1)
    parser.add_argument("--max-speakers", type=int, default=10)
    args = parser.parse_args()

    # Import here so errors are caught properly
    try:
        from pyannote.audio import Pipeline
        import torch
    except ImportError:
        print(json.dumps({"error": "pyannote.audio not installed. Run: pip3 install pyannote.audio"}), file=sys.stdout)
        sys.exit(1)

    # Use pyannote pipeline for speaker diarization
    try:
        # Load the pipeline
        sys.stderr.write("Loading diarization pipeline...\n")
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            use_auth_token=False
        )

        # Use MPS (Metal) if available for acceleration
        if torch.backends.mps.is_available():
            pipeline.to(torch.device("mps"))
            sys.stderr.write("Using Metal GPU\n")

        # Run diarization
        sys.stderr.write(f"Processing: {args.audio_file}\n")

        diarization_params = {}
        if args.num_speakers > 0:
            diarization_params["num_speakers"] = args.num_speakers
        else:
            diarization_params["min_speakers"] = args.min_speakers
            diarization_params["max_speakers"] = args.max_speakers

        diarization = pipeline(args.audio_file, **diarization_params)

        # Convert to JSON
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                "start": round(turn.start, 3),
                "end": round(turn.end, 3),
                "speaker": speaker
            })

        # Map speaker labels to integers
        unique_speakers = list(dict.fromkeys(seg["speaker"] for seg in segments))
        speaker_map = {name: idx for idx, name in enumerate(unique_speakers)}

        for seg in segments:
            seg["speaker"] = speaker_map[seg["speaker"]]

        result = {
            "num_speakers": len(unique_speakers),
            "segments": segments
        }

        print(json.dumps(result))
        sys.stderr.write(f"Done! {len(unique_speakers)} speakers, {len(segments)} segments\n")

    except Exception as e:
        # If the full pipeline fails (needs HF token), fall back to embedding-based approach
        sys.stderr.write(f"Pipeline failed: {e}\n")
        sys.stderr.write("Falling back to embedding-based clustering...\n")

        try:
            from pyannote.audio import Model, Inference
            import numpy as np
            from scipy.cluster.hierarchy import fcluster, linkage
            from scipy.spatial.distance import pdist

            # Load embedding model (doesn't need HF token)
            model = Model.from_pretrained("pyannote/wespeaker-voxceleb-resnet34-LM")
            inference = Inference(model, window="sliding", duration=3.0, step=1.5)

            sys.stderr.write("Extracting speaker embeddings...\n")
            embeddings = inference(args.audio_file)

            # Get embedding data
            data = embeddings.data  # (num_windows, embedding_dim)
            times = embeddings.sliding_window  # timing info

            sys.stderr.write(f"Got {data.shape[0]} embeddings of dim {data.shape[1]}\n")

            if data.shape[0] < 2:
                print(json.dumps({"num_speakers": 1, "segments": [{"start": 0.0, "end": 999.0, "speaker": 0}]}))
                sys.exit(0)

            # Cluster embeddings using agglomerative clustering
            distances = pdist(data, metric="cosine")
            Z = linkage(distances, method="average")

            # Determine number of clusters
            if args.num_speakers > 0:
                labels = fcluster(Z, t=args.num_speakers, criterion="maxclust")
            else:
                # Use distance threshold
                labels = fcluster(Z, t=0.5, criterion="distance")

            labels = labels - 1  # 0-indexed

            # Build segments with timing
            segments = []
            for i, label in enumerate(labels):
                start = times[i].start
                end = times[i].end
                segments.append({
                    "start": round(start, 3),
                    "end": round(end, 3),
                    "speaker": int(label)
                })

            # Merge consecutive same-speaker segments
            merged = []
            for seg in segments:
                if merged and merged[-1]["speaker"] == seg["speaker"] and seg["start"] - merged[-1]["end"] < 0.5:
                    merged[-1]["end"] = seg["end"]
                else:
                    merged.append(dict(seg))

            num_speakers = len(set(seg["speaker"] for seg in merged))
            result = {
                "num_speakers": num_speakers,
                "segments": merged
            }

            print(json.dumps(result))
            sys.stderr.write(f"Done! {num_speakers} speakers, {len(merged)} segments\n")

        except Exception as e2:
            print(json.dumps({"error": str(e2)}))
            sys.exit(1)

if __name__ == "__main__":
    main()
