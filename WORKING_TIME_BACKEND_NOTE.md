# Working-Time Calculation — Note for Backend Team

## Problem
`GET /api/mobile/attendance/summary` returns `minutesWorked` as a simple span:

```
minutesWorked = lastOutAt - firstInAt   (WRONG — counts outside time too)
```

This includes the time the employee spent **outside** the geofence.

Real example (17 Jun 2026):
```json
{
  "firstInAt": "2026-06-17T13:17:56Z",
  "lastOutAt": "2026-06-17T13:54:24Z",
  "minutesWorked": 36   // full 36m28s span; outside time was NOT excluded
}
```

## Required behavior
Count **only the time spent INSIDE the geofence**. The clock must pause while
the user is outside and resume when they re-enter:

```
minutesWorked = sum of all INSIDE segments only
              = (lastOutAt - firstInAt) - (total time spent outside)
```

The mobile app's on-screen timer already does exactly this on the frontend.
The server must do the same when computing the saved `minutesWorked`.

---

## Timer logic the mobile app uses (please replicate server-side)

The app keeps a running total made of "inside segments" and pauses on exit.

State:
- `accumulated`  = time already banked from previous inside-segments (starts 0)
- `segmentStart` = timestamp when the current inside-segment began
                   (null while the user is OUTSIDE / paused)

Algorithm:
```
On CHECK-IN (inside):
    accumulated  = 0
    segmentStart = checkInTime

On crossing OUTSIDE (inside -> outside):
    accumulated += now - segmentStart   // bank the segment just completed
    segmentStart = null                 // PAUSE

On crossing INSIDE (outside -> inside):
    segmentStart = now                  // RESUME a fresh segment

On CHECK-OUT:
    if segmentStart != null:
        accumulated += checkOutTime - segmentStart
    minutesWorked = accumulated         // only inside time
```

"Inside vs outside" is decided by a point-in-polygon test of the GPS
coordinate against the geofence polygon (`GET /api/mobile/geofences`).

---

## The data the server already has
The app reports every geofence transition and a periodic heartbeat to:

```
POST /api/mobile/gps/event
{
  "deviceId": "...",
  "latitude": ...,
  "longitude": ...,
  "accuracyMeters": ...,
  "capturedAt": "...",          // wall-clock IST + "Z"
  "isInsideGeofence": true|false
}
```

- Sent immediately on every boundary crossing (inside<->outside).
- Sent every 5 minutes while tracking (both inside and outside).
- The backend response already includes `geofenceEventRecorded` and
  `violationRecorded`, so the server already knows the inside/outside timeline
  per `deviceId` per day.

## Server-side change needed
When computing `minutesWorked` for a day:
1. Take the stored GPS events for that `deviceId` between `firstInAt` and `lastOutAt`.
2. Build inside/outside intervals from the `isInsideGeofence` transitions
   (or recompute inside/outside from coordinates, as you already do).
3. Sum only the INSIDE intervals → that is `minutesWorked`.

## Acceptance test
1. Check in inside the geofence.
2. Stay inside ~10 min, go outside ~10 min, return inside ~5 min, check out.
3. Span `lastOutAt - firstInAt` ≈ 25 min, but `minutesWorked` should be ≈ 15 min
   (the ~10 outside minutes excluded).

## Status
- Mobile app: DONE. It pauses the on-screen timer when outside and sends
  accurate inside/outside GPS events (every 5 min + on every crossing).
- Backend: PENDING. Update the `minutesWorked` calculation to subtract the
  time spent outside the geofence, using the GPS events above.

---

# Second issue — Admin "Event Log" must show periodic outside updates

## Observed
On the admin "Employee Timeline > Event Log" page, only geofence TRANSITIONS
appear (one row when direction changes In->Out or Out->In, e.g. 12 Jun: "Out -
Geofence exit without punch", "In - Returned to geofence"). The periodic
"still outside" points the app sends every 5 minutes do NOT create rows,
because the backend de-duplicates same-state points
(`skippedSameGeofenceStateCount` in the POST /api/mobile/gps/event response).

Also, in some sessions only an "In" row appears and no "Out" — this happens
when either (a) the device never actually left the fence, or (b) a previous
session left a stale "outside" state so the new outside point is treated as
same-state and skipped.

## Requested behavior
1. While the user is OUTSIDE, the admin Event Log should receive an update
   every 5 minutes (a "still outside" entry), not only the single Out
   transition. The app already POSTs an outside point every 5 minutes with
   `isInsideGeofence: false` — the backend should log/surface these periodic
   points instead of de-duplicating them away.
2. The Out transition and the In (return) transition must always be recorded
   reliably, independent of any stale previous-session state.

## Note
The mobile app already sends:
- An immediate event the moment the user crosses OUT (`isInsideGeofence: false`).
- An event every 5 minutes while still outside (`isInsideGeofence: false`).
- An immediate event when returning IN (`isInsideGeofence: true`).
So all the data is reaching POST /api/mobile/gps/event. Only the backend's
de-duplication / Event-Log logic needs to change to display the periodic
outside updates.
