import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the offset between the server's clock and this device's, per
/// Phase 3b spec A6. QR check-in codes are only valid for a narrow time
/// window, and cheap Android clocks drift — trusting the device clock
/// outright breaks that silently, in the field, for exactly the people
/// least equipped to diagnose why.
///
/// The offset comes from the `Date` header already present on every
/// HTTP response (see AuthInterceptor.onResponse) rather than a
/// dedicated endpoint — that's free, and a dedicated endpoint would
/// collide with /me/qr-secret/'s own throttle.
///
/// In-memory for the hot path (`now()` can be called often — e.g. once
/// per QR code regeneration — and must be synchronous); written through
/// to SharedPreferences only when the offset actually changes, so a
/// cold start while offline still has the last known value. Never
/// secure storage — this is a clock delta, a few bytes with no security
/// value on its own, not a credential.
class ServerClock {
  ServerClock() {
    ready = _hydrate();
  }

  static const _prefsKey = 'server_clock_offset_ms';

  // The `Date` header has one-second resolution; DateTime.now() has
  // sub-millisecond resolution. Comparing a freshly computed offset
  // against the last one for equality therefore almost never matches —
  // it differs by up to ~1 second on nearly every response even with
  // zero real clock drift, purely from that resolution mismatch. A
  // 2-second threshold treats that as noise; only a difference at least
  // this large is treated as the offset having actually moved.
  static const _writeThreshold = Duration(seconds: 2);

  Duration _offset = Duration.zero;
  // What's currently persisted to SharedPreferences, if anything —
  // deliberately tracked separately from _offset, which now updates on
  // every response regardless of whether that response's value earns a
  // write-through.
  Duration? _lastPersistedOffset;
  // Guards against _hydrate()'s disk read resolving AFTER a real
  // response has already set a fresher offset (both run concurrently
  // from app start) — without this, a slow-to-resolve disk read could
  // clobber a value that's already more current than what's on disk.
  bool _hasLiveOffset = false;

  /// Resolves once the persisted offset (if any) has been loaded.
  /// Nothing needs to await this for correctness — `now()` is always
  /// safe to call, defaulting to a zero offset until either this or
  /// the first real response resolves — but tests use it for
  /// determinism.
  late final Future<void> ready;

  Duration get offset => _offset;

  /// Server-adjusted "now" — never the bare device clock for anything
  /// time-window-sensitive (TOTP-style codes, etc).
  DateTime now() => DateTime.now().toUtc().add(_offset);

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasLiveOffset) return; // a real response already won this race
      final storedMs = prefs.getInt(_prefsKey);
      if (storedMs != null) {
        _offset = Duration(milliseconds: storedMs);
        _lastPersistedOffset = _offset;
      }
    } catch (_) {
      // No persisted value yet, or prefs unavailable — stay at zero
      // until a real response sets it.
    }
  }

  /// Parses a `Date` response header and updates the offset. Never
  /// throws: a missing or malformed header just leaves the current
  /// offset — and therefore `now()` — exactly as it was.
  ///
  /// The in-memory offset is updated on every valid header, unconditionally
  /// — `now()` should always reflect the most recent reading. The disk
  /// write is separately gated on `_writeThreshold`: without that gate,
  /// nearly every response would write, since the header's one-second
  /// resolution against DateTime.now()'s sub-millisecond resolution means
  /// the computed offset essentially never repeats exactly, even with no
  /// real drift at all.
  Future<void> updateFromDateHeader(String? headerValue) async {
    if (headerValue == null) return;

    final DateTime serverTime;
    try {
      serverTime = HttpDate.parse(headerValue).toUtc();
    } catch (_) {
      return;
    }

    final newOffset = serverTime.difference(DateTime.now().toUtc());
    _hasLiveOffset = true;
    _offset = newOffset;

    final lastPersisted = _lastPersistedOffset;
    if (lastPersisted != null &&
        (newOffset - lastPersisted).abs() < _writeThreshold) {
      return; // within measurement noise of what's already on disk
    }

    _lastPersistedOffset = newOffset;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, newOffset.inMilliseconds);
    } catch (_) {
      // In-memory value is already updated; persistence is best-effort —
      // a future response will just write through again.
    }
  }
}

/// One shared instance: AuthInterceptor updates it on every response,
/// the member card (Phase 3b Part B, next step) reads it to generate
/// codes against server-adjusted time instead of the device clock.
final serverClockProvider = Provider<ServerClock>((ref) => ServerClock());
