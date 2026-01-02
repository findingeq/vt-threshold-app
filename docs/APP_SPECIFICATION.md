# VT Threshold Analyzer - Technical Specification

**Version:** 1.12.0 (Build 35)
**Platform:** iOS (Flutter)
**Last Updated:** January 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Bluetooth Connectivity](#2-bluetooth-connectivity)
3. [VitalPro Data Protocol](#3-vitalpro-data-protocol)
4. [User Inputs & Configuration](#4-user-inputs--configuration)
5. [CUSUM Algorithm](#5-cusum-algorithm)
6. [Data Recording & Export](#6-data-recording--export)
7. [Cloud Integration](#7-cloud-integration)
8. [Workout Flow](#8-workout-flow)
9. [State Management](#9-state-management)

---

## 1. Overview

### 1.1 Purpose

The VT Threshold Analyzer is a real-time respiratory monitoring application designed to help athletes and coaches detect ventilatory threshold crossings during exercise. It uses the CUSUM (Cumulative Sum) statistical method to identify when minute ventilation (VE) rises above a user-defined threshold, providing immediate visual feedback through a color-coded zone system.

### 1.2 Core Capabilities

- Real-time Bluetooth Low Energy (BLE) connection to VitalPro breathing sensor and heart rate monitor
- Two-stage signal filtering (median filter + time binning) to reduce noise
- CUSUM-based threshold detection with configurable sensitivity
- Visual zone feedback (green/yellow/red) based on proximity to threshold
- Support for interval workouts with automatic CUSUM reset between intervals
- CSV data export for post-workout analysis
- Cloud synchronization for ML-calibrated threshold values

### 1.3 Key Metrics

| Metric | Description | Source |
|--------|-------------|--------|
| VE (Minute Ventilation) | Volume of air breathed per minute | VitalPro sensor |
| HR (Heart Rate) | Beats per minute | Heart rate strap |
| CUSUM Score | Cumulative deviation above threshold | Calculated |
| Zone | Current intensity classification | Derived from CUSUM |

---

## 2. Bluetooth Connectivity

### 2.1 Supported Devices

The app connects to two BLE devices:

| Device | Name Prefix | Purpose |
|--------|-------------|---------|
| VitalPro Breathing Sensor | `TYME-` | Provides minute ventilation data |
| Heart Rate Monitor | `TymeHR` | Provides heart rate data |

### 2.2 BLE Service & Characteristic UUIDs

**VitalPro Breathing Sensor:**

| Component | UUID |
|-----------|------|
| Primary Service | `40b50000-30b5-11e5-a151-feff819cdc90` |
| Breathing Data Characteristic | `40b50004-30b5-11e5-a151-feff819cdc90` |

**Heart Rate Monitor (Standard BLE Heart Rate Profile):**

| Component | UUID |
|-----------|------|
| Heart Rate Service | `180d` |
| Heart Rate Measurement | `2a37` |

**Battery Service (Both Devices):**

| Component | UUID |
|-----------|------|
| Battery Service | `180f` |
| Battery Level | `2a19` |

### 2.3 Connection Parameters

| Parameter | Value |
|-----------|-------|
| Scan Timeout | 15 seconds |
| Connection Timeout | 15 seconds |
| Reconnection Attempts | 6 maximum |
| Reconnection Delay | 5 seconds between attempts |

### 2.4 Reconnection Behavior

When a sensor disconnects during an active workout:
1. The app automatically initiates reconnection
2. Up to 6 reconnection attempts are made at 5-second intervals
3. Reconnection only occurs when a workout is actively running
4. When reconnection succeeds, data collection resumes seamlessly
5. Time gaps during disconnection are handled through interpolation (see Section 6.4)

### 2.5 Data Streams

The BLE service provides two continuous data streams:

- **Breathing Data Stream:** Delivers raw VitalPro packets as byte arrays with timestamps
- **Heart Rate Stream:** Delivers integer heart rate values in BPM

---

## 3. VitalPro Data Protocol

### 3.1 Packet Structure

The VitalPro sensor transmits 17-byte packets via BLE notifications. The app only processes Type 1 packets (respiratory events).

**Type 1 Packet Layout:**

| Byte Position | Field | Data Type | Description |
|---------------|-------|-----------|-------------|
| 0 | Packet ID | uint8 | Must equal 0x01 for Type 1 |
| 1-4 | Tick Counter | uint32 (little-endian) | Time since device power-on |
| 5-12 | Reserved | — | Unused fields |
| 13-14 | VE Raw | uint16 (little-endian) | Minute ventilation in L/min |
| 15-16 | Reserved | — | Duplicate/smoothed values |

### 3.2 Packet Validation

A packet is considered valid when:
- Total length equals exactly 17 bytes
- First byte (Packet ID) equals 0x01

Invalid packets are silently discarded.

### 3.3 Timing and Tick Counter

The tick counter provides relative timing since device power-on. Key parameters:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Tick Rate | 25 ticks per second | Empirically measured |
| Rollover Threshold | 65,536 | Defensive handling for 16-bit counter |

**Time Calculation:**
- Elapsed seconds = (current ticks - anchor ticks) / 25.0
- The anchor is set when the first valid packet is received in each phase

**Rollover Handling:**
- The parser maintains an accumulator for tick overflow
- When raw ticks decrease (indicating rollover), the rollover threshold is added
- This allows continuous elapsed time calculation across device restarts

### 3.4 Time Anchoring

Each workout phase establishes a time anchor:
1. When the first valid packet arrives, the current tick count becomes the anchor
2. The wall clock time at that moment is recorded
3. All subsequent timestamps are calculated relative to this anchor
4. The anchor resets when a new phase begins

### 3.5 Heart Rate Packet Format

Heart rate monitors use the standard BLE Heart Rate Profile:

| Byte | Content | Notes |
|------|---------|-------|
| 0 | Flags | Bit 0: 0=8-bit HR, 1=16-bit HR |
| 1 (or 1-2) | Heart Rate | Value in BPM |

The app reads the flags byte to determine whether the heart rate value is 8-bit or 16-bit.

---

## 4. User Inputs & Configuration

### 4.1 VT Thresholds

The primary user inputs are the two ventilatory thresholds, typically determined from a prior ramp test:

| Threshold | Description | Default | Range | Persistence |
|-----------|-------------|---------|-------|-------------|
| VT1 | First ventilatory threshold (moderate intensity ceiling) | 60.0 L/min | 1-200 | SharedPreferences + Cloud |
| VT2 | Second ventilatory threshold (heavy intensity ceiling) | 80.0 L/min | 1-200 | SharedPreferences + Cloud |

**UI Interaction:**
- Display shows current value with +/- buttons for 1.0 L/min adjustments
- Tapping the value opens a numeric input dialog for direct entry
- Changes are immediately saved locally and synced to cloud

### 4.2 Run Types

The app supports three run intensity categories:

| Run Type | Threshold Used | Sigma Default | Typical Use Case |
|----------|----------------|---------------|------------------|
| Moderate | VT1 | 10% | Endurance runs below first threshold |
| Heavy | VT2 | 5% | Tempo runs between VT1 and VT2 |
| Severe | VT2 | 5% | High-intensity above VT2 |

All run types support interval training with identical configuration options.

### 4.3 Speed Configuration

| Parameter | Range | Default | Increment | Unit |
|-----------|-------|---------|-----------|------|
| Main Speed | 0.5-99.0 | 7.5 | 0.1 | mph |
| Warmup Speed | 0.5-99.0 | 5.0 | 0.1 | mph |
| Cooldown Speed | 0.5-99.0 | 5.0 | 0.1 | mph |

Speed values are informational and recorded in the data export. The app does not control treadmill speed.

### 4.4 Interval Configuration

| Parameter | Range | Default | Notes |
|-----------|-------|---------|-------|
| Number of Intervals | 1-99 | 12 | Single interval = continuous run |
| Work Duration | 0.5-999 minutes | 4.0 | Active exercise period |
| Recovery Duration | 0-999 minutes | 1.0 | Rest between intervals |

**Behavior Notes:**
- When intervals = 1, recovery duration is disabled and set to 0
- Total workout time = (intervals × work) + ((intervals - 1) × recovery)
- CUSUM resets at the start of each work interval (not during recovery)

### 4.5 Warmup & Cooldown

| Parameter | Range | Default | Notes |
|-----------|-------|---------|-------|
| Warmup Duration | 0-999 minutes | 0 (disabled) | Always uses VT1 threshold |
| Cooldown Duration | 0-999 minutes | 0 (disabled) | Always uses VT1 threshold |

When enabled, warmup and cooldown phases:
- Use VT1 as the baseline threshold regardless of selected run type
- Use the moderate sigma value (10% or calibrated)
- Operate in continuous mode (no intervals)
- Display independently on the chart without resetting between phases

### 4.6 Sigma Values (CUSUM Sensitivity)

Sigma controls CUSUM sensitivity - lower values make detection more sensitive:

| Parameter | Default | Range | Notes |
|-----------|---------|-------|-------|
| Sigma Moderate | 10% | Calibrated from cloud | Higher tolerance for VT1 runs |
| Sigma Heavy | 5% | Calibrated from cloud | Tighter detection for VT2 runs |
| Sigma Severe | 5% | Calibrated from cloud | Same as heavy |

Users do not directly edit sigma values. They are:
- Set to defaults on first app launch
- Updated silently via cloud sync based on ML calibration
- Stored locally in SharedPreferences

### 4.7 User Identification

Each app installation generates a unique identifier:

| Property | Format | Purpose |
|----------|--------|---------|
| User ID | UUID v4 | Links device to cloud calibration data |

The user ID is:
- Generated automatically on first launch
- Persisted permanently in SharedPreferences
- Sent with all cloud API requests
- Never displayed to or editable by the user

---

## 5. CUSUM Algorithm

### 5.1 Algorithm Overview

CUSUM (Cumulative Sum) is a sequential analysis technique used to detect shifts in a process mean. In this application, it detects when minute ventilation rises above the user's threshold, indicating they are exceeding their target intensity.

**Key Characteristics:**
- One-sided upper CUSUM (detects increases only)
- No blanking or calibration period - starts immediately
- Baseline provided by user (not calculated from data)
- Two-stage filtering reduces noise before CUSUM calculation

### 5.2 Two-Stage Filtering

Raw VE data from the sensor is noisy. Two filtering stages smooth the signal before CUSUM analysis:

**Stage 1: Per-Breath Median Filter**

| Parameter | Value |
|-----------|-------|
| Window Size | 9 breaths |
| Output | Median of last 9 VE values |
| Warm-up Period | First 9 breaths use partial window |

The median filter removes outliers and transient spikes while preserving the underlying trend.

**Stage 2: Time-Based Binning**

| Parameter | Value |
|-----------|-------|
| Bin Duration | 4 seconds |
| Output | Average of all filtered VE values within the bin |
| Update Rate | Once per completed bin |

Time binning further smooths the data and provides consistent update intervals regardless of breathing rate.

### 5.3 CUSUM Parameters

The CUSUM algorithm uses three derived parameters calculated from sigma:

| Parameter | Symbol | Formula | Purpose |
|-----------|--------|---------|---------|
| Sigma | σ | (sigmaPct / 100) × baselineVe | Standard deviation estimate |
| Slack | K | 0.5 × σ | Prevents small deviations from accumulating |
| Threshold | H | 5.0 × σ | Alarm trigger level |

**Example Calculation (VT2 = 80 L/min, sigmaPct = 5%):**
- σ = 0.05 × 80 = 4.0 L/min
- K = 0.5 × 4.0 = 2.0 L/min
- H = 5.0 × 4.0 = 20.0 L/min

### 5.4 CUSUM Update Logic

For each completed 4-second bin:

1. Calculate residual: `residual = binAvgVe - baselineVe`
2. Update CUSUM: `newCusum = max(0, currentCusum + residual - K)`
3. Track peak: `peakCusum = max(peakCusum, newCusum)`
4. Check alarm: if `newCusum >= H`, trigger alarm

**Key Behaviors:**
- CUSUM cannot go negative (resets to 0)
- Slack parameter (K) means small positive residuals don't accumulate
- Only sustained elevation above threshold causes CUSUM to grow
- Once alarm triggers, it remains triggered for the phase

### 5.5 Zone Classification

The normalized CUSUM score determines the displayed zone:

| Zone | Color | Normalized Score Range | Meaning |
|------|-------|------------------------|---------|
| Green | Green | 0.0 to 0.5 | Well below threshold |
| Yellow | Yellow/Amber | 0.5 to 1.0 | Approaching threshold |
| Red | Red | Above 1.0 | Threshold exceeded |

**Normalized Score Calculation:**
- Normalized = cusumScore / H
- Clamped to range 0.0 - 1.5 for display purposes

### 5.6 Interval Reset Behavior

For interval workouts (numIntervals > 1):

**At start of each work interval:**
- CUSUM score resets to 0
- Peak CUSUM resets to 0
- Alarm state resets to false
- Median filter buffer clears
- Bin buffer clears
- Time anchor resets

**During recovery periods:**
- CUSUM continues from previous state (no reset)
- Zone color changes to recovery grey
- Data is tagged as recovery in export

This allows each interval to be evaluated independently while preserving the recovery context.

### 5.7 Trend Line Smoothing (LOESS)

For chart visualization, raw bin averages are smoothed using LOESS (Locally Estimated Scatterplot Smoothing):

| Parameter | Value |
|-----------|-------|
| Bandwidth | 0.4 (40% of data points) |
| Weight Function | Tricube: (1 - u³)³ |
| Method | Local weighted linear regression |

LOESS creates a smooth trend line that:
- Follows the overall VE trajectory
- Filters out noise and fluctuations
- Updates in real-time as new bins complete

---

## 6. Data Recording & Export

### 6.1 Data Point Structure

Each breath event is recorded with the following fields:

| Field | Type | Description |
|-------|------|-------------|
| Timestamp | ISO 8601 UTC | Wall clock time of measurement |
| Elapsed Seconds | Decimal (3 places) | Time since phase start |
| VE | Integer | Minute ventilation in L/min |
| HR | Integer (optional) | Heart rate in BPM |
| Phase | String | "warmup", "workout", or "cooldown" |
| Is Recovery | Boolean | True during recovery periods |
| Speed | Decimal (1 place) | Configured speed in mph |

### 6.2 Recording Lifecycle

**Session Start (per phase):**
1. Set current phase name
2. Create metadata (first phase only)
3. Initialize tracking variables
4. Begin accumulating data points

**During Recording:**
- Each parsed VitalPro packet adds a data point
- Heart rate updates are attached to subsequent breath events
- Recovery state is tracked and tagged
- Speed changes are captured in real-time

**Session End:**
- Data remains in memory for export
- Multiple export attempts are supported
- Data clears when user starts a new workout or after successful upload

### 6.3 CSV Export Format

**File Naming Convention:**
`YYYY-MM-DD_runtype_session.csv`

Example: `2026-01-02_moderate_session.csv`

**File Structure:**

The CSV file begins with metadata comments (lines starting with #):
- Date of workout
- Run type (moderate/heavy/severe)
- Speed in mph
- VT1 and VT2 thresholds
- Interval configuration (if applicable)

Following metadata, a header row defines columns:
- timestamp, elapsed_sec, VE, HR, phase, speed

Data rows follow with one row per breath event.

### 6.4 Gap Detection and Interpolation

When the breathing sensor disconnects temporarily, data gaps occur. The app handles these through interpolation:

| Parameter | Value |
|-----------|-------|
| Gap Threshold | 5 seconds |
| Interpolation Interval | 3 seconds |
| Method | Linear interpolation |

**Process:**
1. Detect when elapsed time gap exceeds 5 seconds
2. Calculate number of interpolation points needed (gap / 3 seconds)
3. Create synthetic data points with linearly interpolated VE values
4. Insert interpolated points before the actual data point

This ensures:
- Chart continuity during brief disconnections
- Reasonable VE estimates for the gap period
- Accurate elapsed time tracking

### 6.5 Phase Summary Statistics

After each phase, the app can calculate summary statistics:

| Metric | Calculation | Notes |
|--------|-------------|-------|
| Average HR | Mean of all HR values | Only from points with HR data |
| Average VE | Mean of all VE values | Excludes recovery for intervals |
| Terminal Slope | VE drift rate in final 30 seconds | Intervals only |
| Data Point Count | Total valid breath events | Per phase |

**Terminal Slope Calculation:**
- Measures VE trajectory in the last 30 seconds of each interval
- Formula: ((endVE - startVE) / startVE) × 100 / timeDiffMinutes
- Expressed as percent change per minute
- Averaged across all intervals
- Indicates fatigue accumulation within intervals

---

## 7. Cloud Integration

### 7.1 Cloud API Endpoints

The app communicates with a backend service for data storage and ML calibration:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/upload` | POST | Upload workout CSV data |
| `/api/calibration/params` | GET | Fetch calibrated thresholds and sigma values |
| `/api/calibration/set-ve-threshold` | POST | Sync manual threshold changes |

**Base URL:** `https://web-production-11d09.up.railway.app`

### 7.2 Workout Data Upload

**Request:**
- Filename (generated from date and run type)
- Full CSV content as string

**Response:**
- HTTP 200 on success
- Error message on failure

**Behavior:**
- Upload requires non-empty workout data
- Throws exception if no data available
- Does not clear data on upload (allows retry)

### 7.3 Calibration Parameter Sync

**Fetch Calibrated Parameters (App Launch):**

Request includes user_id query parameter.

Response contains:
- vt1_ve: Calibrated VT1 threshold
- vt2_ve: Calibrated VT2 threshold
- sigma_pct_moderate: Calibrated sigma for moderate runs
- sigma_pct_heavy: Calibrated sigma for heavy runs
- sigma_pct_severe: Calibrated sigma for severe runs
- last_updated: Timestamp of last calibration

**Application Logic:**
1. Compare cloud VT values to local values
2. If difference >= 1 L/min, show confirmation dialog
3. User can accept (apply) or reject (keep current)
4. Sigma values always apply silently (no prompt)
5. Rejected cloud values do not overwrite local values

### 7.4 Manual Threshold Sync

When the user manually changes VT1 or VT2:

1. Local value updates immediately
2. Value persists to SharedPreferences
3. API call syncs new value to cloud
4. Cloud resets Bayesian calibration anchor

This ensures:
- User changes take effect immediately
- Cloud tracks the user's manual baseline
- Future ML calibration starts from user's chosen value

### 7.5 Sync Behavior Summary

| Action | Local | Cloud | Bayesian Posterior |
|--------|-------|-------|-------------------|
| App launch fetch | May update (with confirmation) | — | — |
| User approves cloud suggestion | Updates | Already there | Resets |
| User rejects cloud suggestion | Unchanged | Unchanged | Resets |
| User manually changes threshold | Updates | Syncs | Resets |
| Sigma values from cloud | Updates silently | — | N/A |

---

## 8. Workout Flow

### 8.1 Pre-Workout Setup

**Start Screen:**
1. Display and allow editing of VT1 and VT2 thresholds
2. Connect breathing sensor (scan for TYME-* devices)
3. Connect heart rate sensor (scan for TymeHR devices)
4. Show battery levels for connected devices
5. Sync calibrated parameters from cloud
6. Enable Continue button when both sensors connected

**Run Format Screen:**
1. Select run type (Moderate/Heavy/Severe)
2. Configure speed
3. Set number of intervals, work duration, recovery duration
4. Optionally enable warmup and/or cooldown with durations
5. Review total workout time
6. Start workout

### 8.2 Countdown

Before each phase begins:
- 3-second countdown displays
- User can cancel during countdown
- Phase starts when countdown reaches zero

### 8.3 Phase Execution

**Warmup Phase (if enabled):**
- Uses VT1 threshold
- Uses moderate sigma value
- Continuous mode (no intervals)
- Duration configurable (default disabled)
- Ends automatically or via skip button

**Main Workout Phase:**
- Uses selected threshold (VT1 for moderate, VT2 for heavy/severe)
- Uses appropriate sigma value
- Interval mode if numIntervals > 1
- Tracks work and recovery periods separately
- CUSUM resets at start of each work interval

**Cooldown Phase (if enabled):**
- Uses VT1 threshold
- Uses moderate sigma value
- Continuous mode
- Duration configurable
- Ends automatically or via skip button

### 8.4 Real-Time Display

During workout, the screen shows:
- Current phase name and progress
- Elapsed time and remaining time
- Current interval number (if applicable)
- Live VE reading
- CUSUM score and threshold
- Zone indicator (background color)
- Real-time chart with VE, threshold line, and trend line
- Heart rate (if available)
- Current speed
- Pause/Resume and Stop controls

### 8.5 Zone Background Colors

The workout screen background animates to reflect current zone:

| Zone | Background Color | Opacity |
|------|------------------|---------|
| Green | Accent Green | 50% |
| Yellow | Accent Yellow | 50% |
| Red | Accent Red | 50% |
| Recovery | Muted Grey | 25% |

Transitions animate over 500ms for smooth visual feedback.

### 8.6 Phase Transitions

Between phases:
- Transition screen displays with phase summary
- Next phase previews (if applicable)
- User can proceed or end workout
- 3-second countdown before next phase

### 8.7 Workout Completion

After final phase:
- Summary screen displays
- Export options: CSV share or cloud upload
- Data persists until next workout or successful upload
- User returns to start screen

---

## 9. State Management

### 9.1 Provider Architecture

The app uses Provider for state management with three main providers:

| Provider | Purpose | Scope |
|----------|---------|-------|
| AppState | User preferences, thresholds, sensor status | App-wide |
| BleService | Bluetooth connections and data streams | App-wide |
| WorkoutDataService | Workout recording and export | App-wide |

### 9.2 Persisted State

Values stored in SharedPreferences (survive app restart):

| Key | Type | Default |
|-----|------|---------|
| vt1_ve | double | 60.0 |
| vt2_ve | double | 80.0 |
| sigma_pct_moderate | double | 10.0 |
| sigma_pct_heavy | double | 5.0 |
| sigma_pct_severe | double | 5.0 |
| calibration_user_id | String | Generated UUID v4 |

### 9.3 Session State

Values that exist only during app session:

| State | Location | Cleared When |
|-------|----------|--------------|
| Sensor connections | AppState | App closes or disconnect |
| Current run config | AppState | Workout ends |
| Workout data points | WorkoutDataService | New workout starts |
| CUSUM state | CusumProcessor | Phase/interval ends |
| BLE subscriptions | BleService | Workout ends |

### 9.4 App Lifecycle

**On App Launch:**
1. Initialize Flutter bindings
2. Create AppState instance
3. Load persisted values from SharedPreferences
4. Start app with providers
5. On first frame, sync from cloud

**On App Background:**
- Workout continues (if active)
- BLE connections maintained
- Data continues recording

**On App Foreground:**
- UI refreshes with current state
- No automatic data clearing

**On App Close:**
- All session state lost
- Persisted values remain
- Workout data lost if not exported

### 9.5 Run Configuration Model

RunConfig encapsulates all workout settings:

| Property | Description |
|----------|-------------|
| runType | Enum: moderate, heavy, severe |
| speedMph | Main phase speed |
| numIntervals | Number of work intervals |
| intervalDurationMin | Work period duration |
| recoveryDurationMin | Rest period duration |
| thresholdVe | Active threshold (VT1 or VT2) |
| warmupDurationMin | Warmup duration (0 = disabled) |
| cooldownDurationMin | Cooldown duration (0 = disabled) |
| vt1Ve | VT1 value for reference |
| warmupSpeedMph | Warmup speed |
| cooldownSpeedMph | Cooldown speed |

**Computed Properties:**
- hasWarmup: warmupDurationMin > 0
- hasCooldown: cooldownDurationMin > 0
- cycleDurationSec: (intervalDuration + recoveryDuration) × 60
- intervalDurationSec: intervalDuration × 60
- recoveryDurationSec: recoveryDuration × 60

---

## Appendix A: Key Formulas

| Concept | Formula |
|---------|---------|
| Elapsed Time | (currentTicks - anchorTicks) / 25.0 seconds |
| Sigma | (sigmaPct / 100) × baselineVe |
| Slack (K) | 0.5 × sigma |
| Threshold (H) | 5.0 × sigma |
| CUSUM Update | max(0, previousCUSUM + residual - K) |
| Residual | binAverageVE - baselineVE |
| Normalized Score | cusumScore / H |
| Terminal Slope | ((endVE - startVE) / startVE) × 100 / timeDiffMinutes |
| Tricube Weight | (1 - u³)³ where u = distance / maxDistance |

---

## Appendix B: Default Values Summary

| Parameter | Default | Notes |
|-----------|---------|-------|
| VT1 Threshold | 60.0 L/min | User configurable |
| VT2 Threshold | 80.0 L/min | User configurable |
| Sigma Moderate | 10% | Cloud calibrated |
| Sigma Heavy/Severe | 5% | Cloud calibrated |
| H Multiplier | 5.0 | Fixed |
| Slack Multiplier | 0.5 | Fixed |
| Median Window | 9 breaths | Fixed |
| Bin Duration | 4 seconds | Fixed |
| LOESS Bandwidth | 0.4 | Fixed |
| Tick Rate | 25/second | Measured from device |
| Gap Threshold | 5 seconds | For interpolation |
| Interpolation Interval | 3 seconds | Point spacing |

---

## Appendix C: File Locations

| Component | Path |
|-----------|------|
| App State | lib/models/app_state.dart |
| BLE Service | lib/services/ble_service.dart |
| VitalPro Parser | lib/services/vitalpro_parser.dart |
| CUSUM Processor | lib/processors/cusum_processor.dart |
| Workout Data Service | lib/services/workout_data_service.dart |
| Start Screen | lib/screens/start_screen.dart |
| Run Format Screen | lib/screens/run_format_screen.dart |
| Workout Screen | lib/screens/workout_screen.dart |
| Theme | lib/theme/app_theme.dart |

---

*Document generated for VT Threshold Analyzer v1.12.0*
