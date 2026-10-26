// punchIntoSegments is the core logic behind Editor Calendar drag-and-drop
// handoffs (see EditorCalendarView's dropHandoff) — it decides how a new
// {editorId, from, to} assignment window trims/splits whatever segments
// already exist. null `from`/`to` represent -Infinity/+Infinity. Getting
// this wrong either loses history (wipes a segment that should have
// survived) or creates overlapping/duplicate ownership for the same day.
import { describe, it, expect } from "vitest";
import * as app from "./_built/app.mjs";

describe("punchIntoSegments", () => {
  it("full reassignment (from:null, to:null) replaces everything", () => {
    const existing = [{ editorId: 1, from: null, to: null }];
    const result = app.punchIntoSegments(existing, { editorId: 2, from: null, to: null });
    expect(result).toEqual([{ editorId: 2, from: null, to: null }]);
  });

  it("partial handoff from a given date forward splits the prior segment", () => {
    // Person A owns everything; hand off to Person B starting 2026-11-05.
    const existing = [{ editorId: 1, from: null, to: null }];
    const result = app.punchIntoSegments(existing, { editorId: 2, from: "2026-11-05", to: null });
    expect(result).toContainEqual({ editorId: 1, from: null, to: "2026-11-04" });
    expect(result).toContainEqual({ editorId: 2, from: "2026-11-05", to: null });
    expect(result).toHaveLength(2);
  });

  it("a temp cover window splits the prior segment on both sides", () => {
    const existing = [{ editorId: 1, from: null, to: null }];
    const result = app.punchIntoSegments(existing, { editorId: 2, from: "2026-11-05", to: "2026-11-07" });
    expect(result).toContainEqual({ editorId: 1, from: null, to: "2026-11-04" });
    expect(result).toContainEqual({ editorId: 2, from: "2026-11-05", to: "2026-11-07" });
    expect(result).toContainEqual({ editorId: 1, from: "2026-11-08", to: null });
    expect(result).toHaveLength(3);
  });

  it("a non-overlapping existing segment is left untouched", () => {
    const existing = [{ editorId: 1, from: "2026-01-01", to: "2026-01-10" }];
    const result = app.punchIntoSegments(existing, { editorId: 2, from: "2026-11-05", to: null });
    expect(result).toContainEqual({ editorId: 1, from: "2026-01-01", to: "2026-01-10" });
    expect(result).toContainEqual({ editorId: 2, from: "2026-11-05", to: null });
  });

  it("stacking two sequential handoffs produces three clean, non-overlapping segments", () => {
    // Person A owns everything. Hand off to B from Wed forward. Then hand
    // off to C from Fri forward. Monday/Tuesday should still be A's,
    // Wed/Thu should still be B's, Fri onward should be C's — this is
    // exactly the "Mon-Tue stay with A, Wed-Sun move to B" example from
    // the original drag-and-drop request.
    let segs = [{ editorId: "A", from: null, to: null }];
    segs = app.punchIntoSegments(segs, { editorId: "B", from: "2026-11-04", to: null }); // Wed
    segs = app.punchIntoSegments(segs, { editorId: "C", from: "2026-11-06", to: null }); // Fri
    expect(segs).toContainEqual({ editorId: "A", from: null, to: "2026-11-03" });
    expect(segs).toContainEqual({ editorId: "B", from: "2026-11-04", to: "2026-11-05" });
    expect(segs).toContainEqual({ editorId: "C", from: "2026-11-06", to: null });
    expect(segs).toHaveLength(3);
  });
});
