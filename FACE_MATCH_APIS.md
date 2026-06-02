# Face Match APIs — Specification

**Project:** HR360Flow — Attendance Mobile App
**Backend:** https://bhsmart.satoop.com
**Last updated:** 2026-06-02

This document specifies all APIs related to **face verification** during attendance check-in/check-out.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                       FLOW                                    │
└──────────────────────────────────────────────────────────────┘

  FIRST CHECK-IN                  SUBSEQUENT CHECK-INS
  ─────────────                   ────────────────────
  Selfie ─► Backend               Selfie ─► Backend
              │                              │
              ▼                              ▼
        reference NULL?              Compare with
              │                       reference
           YES│                              │
              ▼                          ┌───┴───┐
        Save selfie as              Match?    No Match
        reference                    │           │
              │                      ▼           ▼
              ▼                  ✅ Allow    ❌ Reject 403
        ✅ Accept punch          punch + GPS  face_mismatch
```

---

## 1. POST /api/auth/login (existing — needs field update)

Returns auth token + reference photo URL so app knows if face setup is done.

### Request

```
POST /api/auth/login
Content-Type: application/json

{
  "username": "anshu",
  "password": "admin123"
}
```

### Response (200 OK)

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tokenType": "Bearer",
  "expiresInSeconds": 43200,
  "displayName": "Anshu Singh",
  "role": "Employee",
  "employeeId": 3,
  "registrationStatus": "Approved",

  "profilePhotoUrl": "https://bhsmart.satoop.com/uploads/profiles/3.jpg",
  "referencePhotoUrl": "https://bhsmart.satoop.com/uploads/reference/3.jpg",
  "faceSetupDone": true
}
```

### Notes
- `profilePhotoUrl` — full HTTPS URL (already added). `null` if no photo.
- `referencePhotoUrl` — **NEW** — HTTPS URL of face reference photo. `null` if first-time user.
- `faceSetupDone` — **NEW** — boolean. `false` if user must complete first check-in to set reference.

---

## 2. GET /api/mobile/me (existing — needs field update)

Same face-related fields as login.

### Request

```
GET /api/mobile/me
Authorization: Bearer <token>
Accept: application/json
```

### Response (200 OK)

```json
{
  "employeeId": 3,
  "employeeCode": "ans008",
  "displayName": "Anshu Singh",
  "email": "anshu@test.com",
  "mobileNo": "9876543210",
  "departmentName": "Engineering",
  "shiftName": "Day Shift",
  "shiftWindow": "09:00-18:00",
  "presenceState": "OffDuty",
  "gpsTrackingActive": false,
  "vehicles": [],

  "profilePhotoUrl": "https://bhsmart.satoop.com/uploads/profiles/3.jpg",
  "referencePhotoUrl": "https://bhsmart.satoop.com/uploads/reference/3.jpg",
  "faceSetupDone": true,
  "faceSetupAt": "2026-06-01T09:15:00.000Z"
}
```

### Notes
- Same `referencePhotoUrl`, `faceSetupDone` as login.
- `faceSetupAt` — **NEW** — when face reference was first captured. `null` if not set.

---

## 3. POST /api/mobile/attendance/punch (existing — needs face logic)

Already accepts `selfie`, `FaceMatchStatus`, `FaceMatchScore` per Swagger. Backend just needs to implement the matching logic.

### Request

```
POST /api/mobile/attendance/punch
Authorization: Bearer <token>
Content-Type: multipart/form-data

Form fields:
  Latitude          : 28.6213           (number, double)
  Longitude         : 77.0617           (number, double)
  Direction         : 1                 (integer: 1=CheckIn, 2=CheckOut)
  AccuracyMeters    : 8.5               (number)
  DeviceTimestamp   : 2026-06-02T11:30:00.000Z   (ISO 8601)
  DeviceId          : flutter-xxx-yyy   (string)
  FaceMatchStatus   : true              (boolean, client-reported)
  FaceMatchScore    : 1.0               (number 0..1, client-reported)
  selfie            : <binary jpg/png>  (file)
```

### Backend logic to implement

```pseudocode
IF user.reference_photo_url IS NULL:
    // FIRST CHECK-IN — set reference
    save selfie to storage
    user.reference_photo_url = saved URL
    user.face_setup_at = NOW()
    save user

    accept punch
    save punch_log with selfie_url + face_match_score = 1.0

    RETURN 200 OK with body:
    {
      "success": true,
      "punchId": 123,
      "direction": 1,
      "punchTime": "2026-06-02T11:30:00.000Z",
      "faceSetup": "completed",
      "message": "Face reference photo saved successfully"
    }

ELSE:
    // SUBSEQUENT CHECK-IN — compare
    similarity = face_match_service.compare(
        selfie,
        user.reference_photo_url
    )

    IF similarity >= 0.70:
        accept punch
        save punch_log with selfie_url + face_match_score = similarity

        RETURN 200 OK with body:
        {
          "success": true,
          "punchId": 124,
          "direction": 1,
          "punchTime": "2026-06-02T11:30:00.000Z",
          "faceMatchScore": 0.87,
          "message": "Face verified successfully"
        }

    ELSE:
        RETURN 403 Forbidden with body:
        {
          "success": false,
          "error": "face_mismatch",
          "faceMatchScore": 0.42,
          "threshold": 0.70,
          "message": "Face does not match registered employee. Please retry or contact admin."
        }
```

### Response — Check-IN success (subsequent)

```json
HTTP 200 OK

{
  "success": true,
  "punchId": 124,
  "direction": 1,
  "punchTime": "2026-06-02T11:30:00.000Z",
  "faceMatchScore": 0.87,
  "message": "Face verified successfully"
}
```

### Response — Check-IN first-time

```json
HTTP 200 OK

{
  "success": true,
  "punchId": 123,
  "direction": 1,
  "punchTime": "2026-06-02T11:30:00.000Z",
  "faceSetup": "completed",
  "message": "Face reference photo saved successfully"
}
```

### Response — Face mismatch

```json
HTTP 403 Forbidden

{
  "success": false,
  "error": "face_mismatch",
  "faceMatchScore": 0.42,
  "threshold": 0.70,
  "message": "Face does not match registered employee. Please retry or contact admin."
}
```

### Response — Check-OUT success (with geofence duration)

```json
HTTP 200 OK

{
  "success": true,
  "punchId": 125,
  "direction": 2,
  "punchTime": "2026-06-02T18:30:00.000Z",
  "faceMatchScore": 0.91,
  "geofenceDuration": {
    "insideMinutes": 480,
    "outsideMinutes": 30,
    "unknownMinutes": 5
  },
  "message": "Checked out successfully"
}
```

### Other error responses

```json
HTTP 400 Bad Request — selfie missing
{
  "success": false,
  "error": "selfie_required",
  "message": "Selfie file is required for check-in"
}

HTTP 400 Bad Request — invalid file
{
  "success": false,
  "error": "invalid_selfie",
  "message": "Uploaded file is not a valid image"
}

HTTP 422 Unprocessable Entity — face not detected
{
  "success": false,
  "error": "no_face_detected",
  "message": "No face detected in selfie. Ensure good lighting and face is visible."
}
```

---

## 4. POST /api/mobile/face/verify (NEW — optional but useful)

Pre-validate selfie before punch. Useful for app to show "Face matched, processing check-in..." UX.

### Request

```
POST /api/mobile/face/verify
Authorization: Bearer <token>
Content-Type: multipart/form-data

Form fields:
  selfie : <binary jpg/png>  (file)
```

### Response — Match success

```json
HTTP 200 OK

{
  "matched": true,
  "similarity": 0.87,
  "threshold": 0.70,
  "message": "Face verified"
}
```

### Response — Match failure

```json
HTTP 200 OK

{
  "matched": false,
  "similarity": 0.42,
  "threshold": 0.70,
  "message": "Face does not match"
}
```

### Response — No reference photo yet

```json
HTTP 200 OK

{
  "matched": null,
  "similarity": null,
  "faceSetupDone": false,
  "message": "No reference photo. First check-in will set the reference."
}
```

---

## 5. POST /api/mobile/face/reset (NEW — optional)

Allow user to request face reset (admin approval required) — useful if user's appearance changed (haircut, beard, glasses).

### Request

```
POST /api/mobile/face/reset
Authorization: Bearer <token>
Content-Type: application/json

{
  "reason": "Changed glasses, can't match"
}
```

### Response

```json
HTTP 200 OK

{
  "success": true,
  "requestId": "RESET-2026-0602-001",
  "status": "pending_admin_approval",
  "message": "Face reset request submitted. Admin will review."
}
```

---

## 6. Admin APIs (for face management)

### A. GET /api/admin/employees/{id}/face-reference

Admin views employee's reference photo + match history.

```
GET /api/admin/employees/3/face-reference
Authorization: Bearer <admin-token>

Response:
{
  "employeeId": 3,
  "referencePhotoUrl": "https://bhsmart.satoop.com/uploads/reference/3.jpg",
  "faceSetupAt": "2026-06-01T09:15:00.000Z",
  "recentChecks": [
    {
      "punchId": 124,
      "punchTime": "2026-06-02T09:15:00.000Z",
      "selfieUrl": "https://.../selfies/124.jpg",
      "faceMatchScore": 0.87,
      "matched": true
    },
    ...
  ]
}
```

### B. DELETE /api/admin/employees/{id}/face-reference

Admin clears face reference — user must re-setup on next check-in.

```
DELETE /api/admin/employees/3/face-reference
Authorization: Bearer <admin-token>

Response:
{
  "success": true,
  "message": "Face reference cleared. User must re-setup on next check-in."
}
```

### C. POST /api/admin/employees/{id}/face-reference (upload manual)

Admin uploads reference photo manually (instead of waiting for user's first check-in).

```
POST /api/admin/employees/3/face-reference
Authorization: Bearer <admin-token>
Content-Type: multipart/form-data

Form fields:
  referencePhoto : <binary jpg/png>

Response:
{
  "success": true,
  "referencePhotoUrl": "https://bhsmart.satoop.com/uploads/reference/3.jpg"
}
```

---

## 7. Database Schema Additions

### employees table

| Column | Type | Nullable | Description |
|---|---|---|---|
| `reference_photo_url` | varchar(500) | YES | URL of reference face photo |
| `face_setup_at` | datetime | YES | When reference was first captured |
| `face_setup_method` | varchar(20) | YES | "first_checkin" or "admin_upload" |

### punch_logs table

| Column | Type | Nullable | Description |
|---|---|---|---|
| `selfie_url` | varchar(500) | YES | URL of selfie sent with this punch |
| `face_match_score` | decimal(4,3) | YES | Similarity score 0.000 to 1.000 |
| `face_matched` | boolean | YES | true if score >= threshold |

### face_reset_requests table (optional)

| Column | Type | Description |
|---|---|---|
| `id` | bigint PK | |
| `employee_id` | bigint FK | |
| `reason` | text | |
| `status` | varchar(20) | pending, approved, rejected |
| `requested_at` | datetime | |
| `reviewed_by` | bigint FK | Admin user id |
| `reviewed_at` | datetime | |

---

## 8. Face Matching Service Options

Backend can use any of these:

| Service | Cost | Accuracy | Notes |
|---|---|---|---|
| **AWS Rekognition CompareFaces** | $0.001/check | 99%+ | Easiest, accurate, requires AWS account |
| **Azure Face API** | Free 30k/mo | 95%+ | Good for MS stack |
| **Google Cloud Vision** | $1.50/1k | 95%+ | Decent option |
| **face-api.js** (Node.js) | Free, self-host | 90% | Open source, runs on server |
| **DeepFace** (Python) | Free, self-host | 95% | Best self-hosted option |
| **OpenCV + dlib** | Free | 85% | Lightweight, basic |

**Recommendation:** AWS Rekognition for production (easy API), DeepFace for self-hosted.

### AWS Rekognition example

```python
import boto3

client = boto3.client('rekognition')

response = client.compare_faces(
    SourceImage={'Bytes': selfie_bytes},
    TargetImage={'Bytes': reference_bytes},
    SimilarityThreshold=70
)

if response['FaceMatches']:
    similarity = response['FaceMatches'][0]['Similarity'] / 100
    # similarity is 0..1
else:
    similarity = 0
```

---

## 9. App-Side State (current implementation)

### Current behavior
- App sends `FaceMatchStatus=true` and `FaceMatchScore=1.0` as stub (always)
- App sends selfie file with every punch
- Backend should ignore client-reported values and compute its own

### Future enhancement (Phase 2)
- App downloads `referencePhotoUrl` after login
- App uses Google ML Kit + TFLite (MobileFaceNet) to compute on-device match score
- App sends true `FaceMatchScore` from on-device ML
- Backend can verify by recomputing or trust client score with threshold

---

## 10. Implementation Checklist for Backend

- [ ] Add `reference_photo_url`, `face_setup_at`, `face_setup_method` columns to `employees`
- [ ] Add `selfie_url`, `face_match_score`, `face_matched` columns to `punch_logs`
- [ ] Update `POST /api/auth/login` response to include `referencePhotoUrl`, `faceSetupDone`
- [ ] Update `GET /api/mobile/me` response to include same fields + `faceSetupAt`
- [ ] Implement face matching logic in `POST /api/mobile/attendance/punch`:
  - [ ] If no reference → save selfie as reference
  - [ ] If reference exists → compare and reject if mismatch
- [ ] Set up face matching service (AWS Rekognition recommended)
- [ ] Add admin endpoints (`GET/DELETE/POST /api/admin/employees/{id}/face-reference`)
- [ ] Optional: `POST /api/mobile/face/verify` for pre-validation
- [ ] Optional: `POST /api/mobile/face/reset` for user-requested resets
- [ ] Admin dashboard: view selfies + match scores per check-in
- [ ] Admin dashboard: reset face reference button per employee

---

## 11. Testing Scenarios

| # | Scenario | Expected Result |
|---|---|---|
| 1 | New user — first check-in with clear selfie | 200 OK, faceSetup="completed", reference saved |
| 2 | New user — first check-in with no face in selfie | 422, no_face_detected |
| 3 | Existing user — selfie matches reference | 200 OK, faceMatchScore >= 0.70 |
| 4 | Existing user — different person's selfie | 403, face_mismatch |
| 5 | Existing user — blurry/low-quality selfie | 403 or 200 depending on score |
| 6 | Existing user — selfie missing entirely | 400, selfie_required |
| 7 | Existing user — corrupt selfie file | 400, invalid_selfie |
| 8 | Admin clears reference → user check-in | Treated as first-time, sets new reference |
| 9 | Same user, slightly different angle | Should still match (similarity > 0.70) |
| 10 | Same user wearing mask | May fail (depends on service) |

---

## Contact

For clarifications:
- App developer: anshusingh-rajput
- Backend developer: <add name>
