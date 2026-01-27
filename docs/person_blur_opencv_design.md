# Person Blur Scoring with OpenCV: Design Notes

## Goal
Add OpenCV-based person detection to improve the person-blur metric while keeping the scoring library portable and reusable across platforms. The design should be applicable to other tasks that need heavy, platform-specific dependencies (e.g., ML frameworks) without forcing them into the core C/C++ scoring library.

## Background (current structure)
- The scoring logic lives in a C/C++ core with functions such as sharpness, exposure clipping, noise, and motion blur calculations.
- The public API is a C interface (`vp_analyzer`) that aggregates per-metric results into `VpAggregateResult`.
- `VP_METRIC_PERSON_BLUR` already exists as a metric ID but does not yet have a person-aware implementation.

## Design principles (generalizable)
1. **Keep the scoring core dependency-light.**
   - The core library should compile on all target platforms without heavyweight SDKs/frameworks (OpenCV, ML kits, etc.).
   - This preserves portability and allows the same core to be reused in iOS, Android, and server tools.

2. **Push heavyweight, platform-specific logic to the application layer.**
   - When a feature needs a platform-specific dependency, implement that portion in the application layer or a thin adapter module.
   - Only pass minimal, serializable outputs into the core scoring API.

3. **Define a clear “data contract” for handoff.**
   - Introduce a small, stable payload to pass in results (e.g., per-frame person mask, bounding boxes, or a single aggregate score).
   - This allows swapping person detectors (OpenCV, Core ML, etc.) without changing the core scoring logic.

4. **Prefer backward-compatible API extensions.**
   - If new data is needed, add optional/extended structs or new API entry points rather than changing existing ones.
   - Existing callers should continue to work unchanged.

## Recommended architecture (person blur)
### High-level flow
1. **App layer (iOS)**
   - Use OpenCV to perform person detection on each frame (or sampled frames).
   - Produce a lightweight representation:
     - Option A: Per-frame bounding boxes for detected persons.
     - Option B: Per-frame person mask (binary or probabilistic).
     - Option C: A precomputed “person-blur score” per frame.

2. **Core scoring layer**
   - Consume the OpenCV output and compute the person-blur metric consistently with other scores (normalization, aggregation, and reporting via `VpAggregateResult`).
   - Keep aggregation logic in the core to maintain consistent scoring behavior across metrics.

### API extension options
- **Option 1: Extended frame input**
  - Add an optional `VpFrameExtras` struct with person-related data.
  - Extend the analyze entry point to accept extras: `vp_analyze_frames_ex(...)`.
- **Option 2: Metric injection**
  - Add an API for injecting per-frame metric values from outside the core (e.g., `vp_analyze_frames_with_metrics(...)`).
  - The core uses injected values for `VP_METRIC_PERSON_BLUR` while computing other metrics normally.

### Trade-offs
- **Bounding boxes**: Smaller data size, but requires additional logic in core to translate into blur estimation.
- **Mask**: Most flexible for blur estimation but heavier to compute/transfer.
- **Precomputed score**: Simplest core integration but less reusable for other person-related scoring tasks later.

## Decision guideline (for other tasks)
When introducing a new model or heavy dependency:
- **If the dependency is platform-specific** → Keep it out of core; return small outputs into core.
- **If the dependency is small and portable** → Consider adding it to core only if it won’t destabilize build or packaging.
- **If the feature is likely to expand** (e.g., multiple person-related metrics) → Prefer richer outputs (mask/boxes) over a single score.

## Suggested next steps
1. Decide the handoff data format (boxes vs mask vs score).
2. Add the minimal API extension in the core for optional external metric data.
3. Implement OpenCV person detection in the iOS app layer and wire it to the new API.
4. Validate scoring consistency by comparing before/after results on a known sample set.
