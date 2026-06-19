# RuView findings — the pose/skeleton is synthetic

> Heads-up for anyone deploying [RuView / WiFi-DensePose](https://github.com/ruvnet/RuView):
> if you're wondering why a person's **arms never move** in the DensePose UI, this is why.
> Investigated June 2026 against a 3-node ESP32-S3 CSI setup; line refs are into the upstream repo.

**Root finding: there is no real pose sensing anywhere in this system.** The 3-node ESP32 CSI
pipeline genuinely yields presence, person count, motion level, and breathing/HR — but the human
**skeleton is fabricated**. Confirmed in code across three layers:

1. **Observatory UI** (`ui/observatory/js/`) — `figure-pool.js:281` calls `pose-system.js`
   `generateKeypoints()`, which switches purely on a `person.pose` string and animates a canned
   skeleton. It **never reads `persons[].keypoints`** from the live WS payload (grep for
   `.keypoints` in `ui/observatory/js/` = 0 hits). The live `PersonDetection` has no
   `pose`/`position`/`motion_score` fields, so it defaults to `poseStanding` — a fixed ~1cm idle
   sway. That's why arms never move.

2. **Server pose** — `v2/crates/wifi-densepose-sensing-server/src/pose.rs::derive_single_person_pose`
   builds a fixed COCO-17 template (`kp_offsets`) animated by scalar features (motion_band_power,
   breathing_band_power, dominant_freq_hz, variance, tick). Arms (extremity keypoints) get only
   sinusoidal jitter scaled by motion_score. `tracker_bridge.rs` then Kalman-smooths and
   centroid-fills unmapped joints. No ML pose inference in the runtime path (the `adaptive_model`
   is for present/absent classification only).

3. **Training tab** (`training_api.rs`) — a *real* gradient-descent pipeline (records CSI →
   `.csi.jsonl`, trains a regularized linear model, exports `.rvf`, streams progress over
   `/ws/train/progress`). BUT the labels come from `compute_teacher_targets()`
   (`training_api.rs:453`) = the SAME heuristic as `pose.rs`. `RecordedFrame` (`recording.rs:58`)
   stores only `timestamp/subcarriers/rssi/noise_floor/features` — no camera/mocap/keypoints. So
   training is **self-distillation of a hand-crafted heuristic** into a linear model; PCK/MSE look
   great because they're graded against their own synthetic targets. It cannot learn real arms.

**The Sensing tab is the honest view** (`components/SensingTab.js` + `gaussian-splats.js`): the
floor heatmap intensity is real signal disturbance, but its *position* is subcarrier-index-mapped
(`generate_signal_field` in `csi.rs:141`, `angle = k/n_sub*2π`), NOT spatial localization; the
center glow blob is a fixed presence+motion indicator (green=present, red=active, pulses with
breathing), not a body.

**Calibration (`--calibrate` / field model) does NOT fix arms** — it only improves
presence / occupancy-count / motion-baseline (the "10 persons when 1" bug). To get real
WiFi→pose you'd need camera/mocap-synced ground-truth labels (the CMU DensePose-from-WiFi
approach), which this repo never captures.

Context: GitHub issue [ruvnet/RuView#299](https://github.com/ruvnet/RuView/issues/299) reports the
same symptom (HR/BR work, no skeleton movement) and was unanswered at time of writing. See
`SETUP-NOTES.md` for the hardware/server setup these findings were observed on.
