# Timeline Live Mode Selection Reset Fix

## Issue

The Timeline selection was still resetting when live mode was enabled, even after the initial fix for the document refresh reset bug. The selection would visually "jump" every second when live mode was checked, but worked fine when live mode was unchecked.

## Root Cause

The original fix (in `Timeline.jsx:675-721`) prevented view recalculation when only timeline bounds changed. However, it didn't account for **live mode behavior**:

1. **Live mode updates every second** (line 420): `setInterval(..., 1000)`
2. **Live mode shifts the selection range** (lines 427-428): Keeps "now" centered by calculating `newStart` and `newEnd`
3. **This triggers `onDateRangeChange`** (line 432), updating the selection props
4. **The original fix detected this as a selection change** (lines 686-692), because `rangeStart` and `rangeEnd` ARE changing
5. **View was recalculated with padding** (lines 696-720), causing visual "jumps"

**The key insight:** In live mode, the selection range is continuously shifting forward in time (but maintaining the same duration). This is different from a user manually changing the selection.

## Solution

Enhanced the view calculation logic to differentiate between:

1. **Live mode shifts** - Selection moves forward but duration stays the same
   - Smoothly shift the view by the same time delta
   - Don't recalculate padding
   - No visual "jump"

2. **User selection changes** - Duration changes or non-live mode
   - Recalculate view with padding
   - Adjust for boundaries
   - Normal behavior

### Code Changes

**File:** `apps/web/src/components/features/Timeline.jsx` (lines 675-747)

**Added:**
- `prevViewRef` to track previous view bounds (line 677)
- Live mode shift detection (lines 695-702)
- Conditional view update logic (lines 704-746)

**Key logic:**
```javascript
// Check if this is a live mode shift (duration unchanged, just shifted in time)
const prevDuration = prevRangeRef.current.end && prevRangeRef.current.start
  ? prevRangeRef.current.end.getTime() - prevRangeRef.current.start.getTime()
  : 0;
const currentDuration = rangeEnd.getTime() - rangeStart.getTime();
const isLiveModeShift = liveUpdate &&
  prevDuration > 0 &&
  Math.abs(currentDuration - prevDuration) < 100; // Duration unchanged (within 100ms)

if (isLiveModeShift && prevViewRef.current.min && prevViewRef.current.max) {
  // Smoothly shift the view by the same amount the selection shifted
  const timeShift = rangeStart.getTime() - prevRangeRef.current.start.getTime();
  const newViewMin = new Date(prevViewRef.current.min.getTime() + timeShift);
  const newViewMax = new Date(prevViewRef.current.max.getTime() + timeShift);

  setViewMinDate(newViewMin);
  setViewMaxDate(newViewMax);
} else {
  // Not live mode shift - recalculate view with padding
  // (normal behavior for user selection changes)
  ...
}
```

## Testing

### New Tests Added

**File:** `Timeline.regressionSuite.test.jsx`

Added 2 new tests for live mode behavior (now 28 total tests in regression suite):

1. **"should smoothly shift view when live mode advances selection"**
   - Simulates live mode shifting selection forward every second
   - Verifies duration remains constant
   - Ensures smooth view updates

2. **"should handle live mode shifting without visual jumps"**
   - Simulates 10 consecutive 1-second shifts
   - Verifies duration stays constant throughout
   - Tests for stability during continuous live mode operation

3. **"should recalculate view when user changes selection in non-live mode"**
   - Verifies that non-live mode still recalculates with padding
   - Ensures normal behavior isn't broken

### Test Results

```
✓ Timeline.selectionStability.test.jsx (9 tests)
✓ Timeline.regressionSuite.test.jsx (28 tests)  ← +2 new tests
Total: 37 tests passing
```

All tests pass in ~1.7 seconds.

## Impact

### Before (Post-Original Fix)
- ✅ Selection stable when live mode disabled
- ❌ Selection "jumps" every second when live mode enabled
- ❌ View recalculated unnecessarily in live mode
- ❌ Poor user experience with live mode

### After (Live Mode Fix)
- ✅ Selection stable when live mode disabled
- ✅ Selection smoothly shifts when live mode enabled
- ✅ View shifts proportionally without recalculation
- ✅ No visual "jumps" in live mode
- ✅ Excellent user experience in both modes

## Technical Details

### Why Smooth Shifting Works

When live mode is active and the selection shifts:
1. Calculate the time delta: `timeShift = newStart - oldStart`
2. Apply same delta to view: `newViewMin = oldViewMin + timeShift`
3. This keeps the selection in the same visual position relative to the viewport
4. No recalculation of padding = no visual jump

### Why Duration Check Is Important

We check if duration stayed the same (within 100ms tolerance) to distinguish:
- **Live mode shift:** Duration constant, just moving forward
- **User change:** Duration different, user dragged a handle or clicked a shortcut

### Edge Cases Handled

1. **First render:** `prevViewRef.current.min` is null, falls back to normal calculation
2. **Switching to live mode:** First update recalculates, subsequent updates shift smoothly
3. **User changes selection during live mode:** Duration changes, triggers recalculation
4. **Toggling live mode off/on:** Each mode works correctly

## Verification

To verify the fix works:

1. **Test without live mode:**
   ```bash
   # Start app, uncheck "Live" mode
   # Drag selection handles - should work smoothly
   # Wait for document refresh (30s) - should not jump
   ```

2. **Test with live mode:**
   ```bash
   # Start app, check "Live" mode
   # Observe selection shifting forward every second
   # Selection should move smoothly without jumps
   # View should follow selection proportionally
   ```

3. **Test toggling:**
   ```bash
   # Toggle live mode on/off multiple times
   # Selection should remain stable during toggles
   # No unexpected jumps or resets
   ```

## Related Issues

- **Original Issue:** Selection reset during 30-second document refresh
- **Original Fix:** `TIMELINE_SELECTION_FIX.md` (lines 675-721)
- **This Fix:** Enhanced original fix to handle live mode (lines 675-747)

## Files Modified

### Code
- `apps/web/src/components/features/Timeline.jsx` (lines 675-747)
  - Added `prevViewRef` ref
  - Added live mode shift detection
  - Added conditional view update logic

### Tests
- `apps/web/src/components/features/Timeline.regressionSuite.test.jsx`
  - Updated test "should smoothly shift view when live mode advances selection"
  - Added test "should handle live mode shifting without visual jumps"
  - Added test "should recalculate view when user changes selection in non-live mode"
  - Test count: 26 → 28 tests

### Documentation
- `apps/web/TIMELINE_LIVE_MODE_FIX.md` (this file)

## Rollback

If this fix causes issues, you can rollback by reverting the live mode shift detection:

```javascript
// Remove this section (lines 695-714)
const isLiveModeShift = ...
if (isLiveModeShift && ...) {
  // Smooth shift logic
}

// Keep only the else block (lines 716-746)
```

This will revert to the original fix behavior (which fixes non-live mode but not live mode).

## Future Improvements

Consider:
- [ ] Add visual indicator when live mode is shifting
- [ ] Make live mode shift interval configurable
- [ ] Add animation easing for smoother visual experience
- [ ] Performance optimization for high-frequency updates

## Summary

The Timeline live mode selection reset is now fixed. The view smoothly shifts with the selection in live mode without recalculating padding, eliminating visual "jumps". All 37 tests pass, including 2 new tests specifically for live mode behavior.

**Status:** ✅ Fixed and Tested
**Date:** 2025-10-25
**Version:** 1.1.0
