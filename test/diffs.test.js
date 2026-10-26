// Tests for the shadow-write diff functions. These decide what actually
// gets written to Supabase from a "whole array replaced" edit (every
// production/round/ingest edit anywhere in the app funnels through one
// onUpdateProject(id, field, wholeArray) call) — getting insert/update/
// delete detection wrong here either writes nothing (looks like data loss)
// or writes duplicates. The "skip silently when untagged" rule in
// computeProductionDiff specifically is called out in its own comment as
// the fix for a real production-time-edit-freeze bug, so it gets its own
// regression test below.
import { describe, it, expect } from "vitest";
import * as app from "./_built/app.mjs";

describe("computeProductionDiff", () => {
  it("inserts a production with no id match and no _rowId", () => {
    const diff = app.computeProductionDiff([], [{ id: 1, title: "New shoot" }]);
    expect(diff.toInsert).toHaveLength(1);
    expect(diff.toUpdate).toHaveLength(0);
    expect(diff.toDelete).toHaveLength(0);
  });

  it("does NOT insert a production that already carries a _rowId (tag just hasn't round-tripped into local state yet)", () => {
    const diff = app.computeProductionDiff([], [{ id: 1, title: "New shoot", _rowId: "uuid-1" }]);
    expect(diff.toInsert).toHaveLength(0);
  });

  it("skips silently (no insert, no update) for an existing-but-untagged production", () => {
    // This is the exact bug the comment above computeProductionDiff
    // describes: without this skip, every edit to a real production whose
    // _rowId tag hasn't resolved yet looked like a brand-new insert.
    const old = [{ id: 1, title: "Shoot A" }]; // no _rowId — bootstrap tagging hasn't resolved
    const next = [{ id: 1, title: "Shoot A (edited)" }];
    const diff = app.computeProductionDiff(old, next);
    expect(diff.toInsert).toHaveLength(0);
    expect(diff.toUpdate).toHaveLength(0);
  });

  it("produces an update when a tagged production's fields actually changed", () => {
    const old = [{ id: 1, _rowId: "uuid-1", title: "Shoot A", status: "Planning" }];
    const next = [{ id: 1, _rowId: "uuid-1", title: "Shoot A", status: "Approved" }];
    const diff = app.computeProductionDiff(old, next);
    expect(diff.toUpdate).toHaveLength(1);
    expect(diff.toUpdate[0].rowId).toBe("uuid-1");
    expect(diff.toUpdate[0].patch.status).toBe("Approved");
  });

  it("produces no update when nothing actually changed", () => {
    const prod = { id: 1, _rowId: "uuid-1", title: "Shoot A", status: "Planning" };
    const diff = app.computeProductionDiff([prod], [{ ...prod }]);
    expect(diff.toUpdate).toHaveLength(0);
  });

  it("deletes a tagged production that's missing from the new array, but not an untagged one", () => {
    const old = [
      { id: 1, _rowId: "uuid-1", title: "Shoot A" },
      { id: 2, title: "Shoot B (never tagged)" },
    ];
    const diff = app.computeProductionDiff(old, []);
    expect(diff.toDelete).toHaveLength(1);
    expect(diff.toDelete[0].id).toBe(1);
  });
});

describe("computeRoundDiff", () => {
  it("inserts a round whose id isn't a real row uuid yet", () => {
    const diff = app.computeRoundDiff([], [{ id: 12345, label: "Round 1" }]); // uid()-style numeric id
    expect(diff.toInsert).toHaveLength(1);
  });

  it("produces an update when an existing round's fields changed", () => {
    const old = [{ id: "uuid-r1", deliverableRowId: "uuid-d1", label: "Round 1", status: "Pending" }];
    const next = [{ id: "uuid-r1", deliverableRowId: "uuid-d1", label: "Round 1", status: "Approved" }];
    const diff = app.computeRoundDiff(old, next);
    expect(diff.toUpdate).toHaveLength(1);
    expect(diff.toUpdate[0].patch.status).toBe("Approved");
  });

  it("deletes a round missing from the new array", () => {
    const old = [{ id: "uuid-r1", deliverableRowId: "uuid-d1", label: "Round 1" }];
    const diff = app.computeRoundDiff(old, []);
    expect(diff.toDelete).toHaveLength(1);
  });
});

describe("computeIngestDiff", () => {
  it("assigns a stable incrementing seq to each newly inserted ingest", () => {
    const old = [{ id: 1, _rowId: "uuid-ig1" }, { id: 2, _rowId: "uuid-ig2" }];
    const next = [...old, { id: 3 }, { id: 4 }];
    const diff = app.computeIngestDiff(old, next);
    expect(diff.toInsert).toHaveLength(2);
    expect(diff.toInsert.map(i=>i._seq)).toEqual([3, 4]);
  });

  it("deletes a tagged ingest missing from the new array, but not an untagged one", () => {
    const old = [
      { id: 1, _rowId: "uuid-ig1" },
      { id: 2 }, // never tagged
    ];
    const diff = app.computeIngestDiff(old, []);
    expect(diff.toDelete).toHaveLength(1);
    expect(diff.toDelete[0].id).toBe(1);
  });
});
