# 2. Minimum iOS version is 18

- Status: Accepted
- Date: 2026-10-10

## Context

DictationCore 0.1.0 (pinned exactly) supports iOS 18 and later because `CaptureBuffer`, which is
shared with macOS, uses `Synchronization.Mutex`. That type needs iOS 18 and macOS 15.

## Decision

The app and the keyboard extension target iOS 18 or later.

## Consequences

- Devices that can't run iOS 18 are not supported.
- If iOS 17 ever becomes necessary, the fix belongs in DictationCore (a lock that works on
  iOS 17), released as a new tag. Not in this app.
