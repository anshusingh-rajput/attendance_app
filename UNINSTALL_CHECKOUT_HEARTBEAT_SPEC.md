# Requirement 17 — Auto Check-Out on App Uninstall (Heartbeat Timeout)

**Requirement:** *If the application is uninstalled, the system should
automatically mark the user as Checked Out.*

## Background

Android does **not** notify an app when it is being uninstalled — the app's
code and data are removed instantly, so the app cannot make any API call (not
even check-out) at uninstall time. Therefore the check-out **must be triggered
by the backend**, not the app.

The simplest, dependency-free way to do this is a **heartbeat timeout**: the app
already sends a periodic GPS event while the user is checked in; if those events
suddenly stop, the backend treats the user as gone (app uninstalled / killed)
and auto checks them out.

## How it works

1. While a user is **checked in**, the app sends a GPS event every **5 minutes**
   to `POST /api/mobile/gps/event` (this is the "heartbeat"). This already works
   in the app — no app changes are required.
2. When the app is **uninstalled** (or killed / loses connectivity), these
   heartbeat events **stop arriving**.
3. The **backend runs a scheduled job** (e.g. every 5 minutes). For every user
   who is currently checked in, it checks the timestamp of their **last GPS
   event**:
   - If the last event is **older than 20 minutes**, the backend
     **automatically marks the user as Checked Out**, using the **last received
     event's time** as the check-out time.

So roughly **20 minutes after uninstall**, the user is auto checked out by the
server.

## Responsibilities

| Part | Who | Status |
|------|-----|--------|
| Send GPS heartbeat every 5 min while checked in | App | ✅ Already implemented |
| Scheduled job that auto checks-out on heartbeat timeout | Backend | ⬜ To be implemented |

## Backend implementation (to do)

Add a scheduled job (cron / background worker) that runs every ~5 minutes:

```
for each user where status == CHECKED_IN:
    lastEvent = latest GpsTrackPoint for user
    if lastEvent == null:
        continue   // no heartbeat yet; skip
    if (now - lastEvent.capturedAt) > 20 minutes:
        markCheckedOut(
            user,
            checkOutTime = lastEvent.capturedAt,   // last known time
            reason = "AUTO_HEARTBEAT_TIMEOUT"
        )
```

### Notes / tuning
- **Timeout value (20 min):** must be safely larger than the app's 5-minute
  heartbeat interval, so a single missed/delayed event doesn't cause a false
  check-out. 15–30 minutes is reasonable; 20 is a good default.
- **Check-out time:** use the **last received event time**, not "now", so the
  recorded check-out reflects when the user actually stopped sending data
  (≈ when the app was uninstalled).
- Mark these auto check-outs with a flag/reason (e.g. `AUTO_HEARTBEAT_TIMEOUT`)
  so they can be distinguished from manual check-outs in reports.
- This same mechanism also covers other "silent disappearance" cases: phone
  switched off, battery dead, force-stopped app, or no network for a long time.

## Why this approach (vs FCM)

- **No Firebase / `google-services.json` required.**
- **No app changes** — the heartbeat already exists.
- Only the backend scheduled job needs to be added.
- Trade-off: detection takes up to ~20 minutes (vs near-instant with FCM), which
  is acceptable for attendance.
