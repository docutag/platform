# Timeline Selection Stability Fix

## Issue

The timeline control's selected area was randomly resetting, particularly during the 30-second periodic document refresh cycle. Users would observe the green selection handles "jumping" or shifting position even though they hadn't interacted with the timeline.

## Root Cause

The issue was in `Timeline.jsx` lines 675-707, specifically in the view calculation `useEffect`:

```javascript
useEffect(() => {
  if (isDragging || isPanning) return;

  const selectedRange = rangeEnd - rangeStart;
  const padding = selectedRange * 0.5;
  // ... view calculations ...
  setViewMinDate(viewMin);
  setViewMaxDate(viewMax);
}, [rangeStart, rangeEnd, minDate, maxDate, isDragging, isPanning, currentTime]);
```

**The problem:** This effect depended on `minDate`, `maxDate`, and `currentTime`, which change frequently:
- `currentTime` updates every minute (line 636-646)
- `maxDate` updates every minute to extend the timeline into the future (App.jsx lines 51-59)
- `minDate`/`maxDate` change when new documents are added that extend the timeline bounds

Every time these values changed, the view would recalculate, causing the `dateToX` function to return different pixel positions for the same dates. This made the selection handles visually "jump" even though the underlying date range (`startDate`/`endDate`) hadn't changed.

## Solution

Added a ref to track the previous selection range and only update the view when the selection actually changes:

```javascript
// Track previous selection range to detect changes
const prevRangeRef = useRef({ start: null, end: null });

useEffect(() => {
  if (isDragging || isPanning) return;

  // Only update view if the selection actually changed (not just timeline bounds)
  const selectionChanged =
    !prevRangeRef.current.start ||
    !prevRangeRef.current.end ||
    prevRangeRef.current.start.getTime() !== rangeStart.getTime() ||
    prevRangeRef.current.end.getTime() !== rangeEnd.getTime();

  if (!selectionChanged) return;

  prevRangeRef.current = { start: rangeStart, end: rangeEnd };

  // ... view calculations ...
}, [rangeStart, rangeEnd, minDate, maxDate, isDragging, isPanning]);
```

**Key changes:**
1. Added `prevRangeRef` to track the previous selection
2. Check if selection actually changed before updating view
3. Removed `currentTime` from dependency array (unnecessary)
4. View only updates when user explicitly changes the selection, not when timeline bounds change

## Testing

Created comprehensive test suite in `Timeline.selectionStability.test.jsx` covering:

1. **Selection stability during document updates** - Selection should not change when documents are added/removed
2. **Selection stability during bounds changes** - Selection should not reset when `minDate` or `maxDate` change
3. **Regression test for periodic refresh** - Simulates the 30-second refresh cycle to ensure selection stays stable
4. **Edge cases** - Empty documents, rapid updates, etc.

Run tests with:
```bash
cd apps/web && npm test -- Timeline.selectionStability.test.jsx
```

All 9 tests pass successfully.

## Impact

- ✅ Selection no longer "jumps" during document refreshes
- ✅ Selection remains stable when timeline bounds extend
- ✅ Selection remains stable when `maxDate` advances every minute
- ✅ Users can now interact with the timeline without unexpected resets
- ✅ Performance improved by avoiding unnecessary view recalculations

## Files Modified

- `apps/web/src/components/features/Timeline.jsx` - Fixed view calculation logic (lines 675-721)
- `apps/web/src/components/features/Timeline.selectionStability.test.jsx` - New comprehensive test suite

## Related Code

- `apps/web/src/App.jsx` lines 196-214 - Periodic refresh logic that triggered the issue
- `apps/web/src/App.jsx` lines 51-59 - `maxDate` updates every minute
- `apps/web/src/App.jsx` lines 67-72 - `maxDate` updates when scrape requests change
