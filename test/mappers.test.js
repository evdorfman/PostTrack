// Round-trip tests for every rowToX/xToRow DB-mapper pair in the app.
//
// What this catches: a typo'd column name, a field accidentally dropped
// from one side of a pair, a wrong default, or `||` vs `??` picking the
// wrong falsy value — the exact class of bug that silently dropped
// production/project/review-round/deliverable fields on every save this
// session (see production_patch_013/014/016). What this does NOT catch: a
// field that's genuinely new to the UI and was never added to the mapper
// OR this test — that gap can only be closed by a human (or another
// audit pass) noticing the field is missing from both places at once.
//
// Each case builds a representative object with every mapped field set to
// a distinct non-default value, round-trips it through toRow → rowTo, and
// asserts every field survives unchanged. Distinct values (not e.g. two
// fields both `true`) make a swapped-field bug show up as a mismatch
// instead of accidentally still passing.
import { describe, it, expect } from "vitest";
import * as app from "./_built/app.mjs";

describe("rowToTeamMember / teamMemberToRow", () => {
  it("round-trips every field", () => {
    const m = {
      id: 1, name: "Jordan Lee", roles: ["Editor","Producer"], employeeType: "Full-time",
      available: true, active: true, email: "jordan@example.com", phone: "555-0100", department: "Post",
      rate: {type:"hourly", amount: 75}, skills: ["Premiere","After Effects"],
      workHours: {days:[1,2,3,4,5], start:9, end:18, timezone:"PST"},
      assignablePercent: 80, authUserId: "auth-123", isAdmin: false, color: "#6366f1",
    };
    const row = app.teamMemberToRow(m);
    expect(row).toMatchObject({
      employee_type:"Full-time", assignable_percent:80, auth_user_id:"auth-123",
      is_admin:false, work_hours: m.workHours,
    });
    const back = app.rowToTeamMember(row);
    expect(back).toEqual(m);
  });
});

describe("rowToProject / projectToRow", () => {
  it("round-trips every field projectToRow actually persists", () => {
    // deliverables/productions/rounds are deliberately excluded — they live
    // in their own tables now (see projectToRow's own comment) — so this
    // only covers the fields projectToRow still writes.
    const p = {
      id: 5, projectCode:"26_TEST", name:"Test Project", requester:"Alex",
      year:2026, status:"In Production", workstream:"Content Studio", businessUnit:"MKT",
      deadline:"2026-12-01", briefNotes:"Brief text", keywords:["a","b"],
      assignees:{Producer:[1]}, shoots:[], notes:[{text:"note"}], ingestDates:[],
      closedAt:null, bxtvRefs:["ep1"], bxtvMeta:{season:6}, inPipeline:true,
      animation:{groups:[]}, _segments:[{editorId:1,from:null,to:null}],
      budget:[{amount:100}], budgetStatus:"Approved", costCode:"CC-1",
      addedToCompletes:true, basedOnExistingMaterial:false, isBigEvent:true,
      briefSummary:"Summary", clientDescription:"Client desc", pipelineNotes:"Pipeline notes",
      mamProjectLink:"https://mam.example/1", trintProjectLink:"https://trint.example/1",
      projectBrief:{doc:"x"}, intakeIds:[9], rolesNotNeeded:["Animator"],
    };
    const row = app.projectToRow(p);
    const back = app.rowToProject(row);
    // rowToProject also reads deliverables/productions keys that
    // projectToRow doesn't write (they live in their own tables now) —
    // strip those before comparing since they're legitimately out of
    // scope for this pair. shoots IS still written/read by this pair.
    const { deliverables, productions, ...rest } = back;
    expect(rest).toEqual(p);
  });
});

describe("rowToBooking / bookingToRow", () => {
  it("round-trips known fields", () => {
    const b = {
      id:"b1", title:"BXTV Shoot", projectId:5, parentBookingId:null,
      bookingStatus:"Confirmed", productionType:"Content Filming", location:"Studio B",
      startTime:"2026-11-01T09:00", endTime:"2026-11-01T17:00", crewCallTime:"2026-11-01T08:00",
      notes:"Notes", equipmentIds:["eq-1"], confirmations:[{crewId:1,status:"Confirmed"}],
      crewInternal:[{memberId:1,role:"Producer"}], crewExternal:[],
    };
    const row = app.bookingToRow(b);
    expect(row.extra).toEqual({});
    const back = app.rowToBooking(row);
    expect(back).toEqual(b);
  });

  it("round-trips an unknown field through the `extra` jsonb catch-all", () => {
    // rejectionNote is the real example this catch-all exists for — set
    // only on deny, never in BOOKING_KNOWN_FIELDS.
    const b = { id:"b2", title:"Denied booking", rejectionNote:"Missing crew call time" };
    const row = app.bookingToRow(b);
    expect(row.extra).toEqual({ rejectionNote: "Missing crew call time" });
    const back = app.rowToBooking(row);
    expect(back.rejectionNote).toBe("Missing crew call time");
  });
});

describe("rowToDeliverable / deliverableToRow", () => {
  it("round-trips every field deliverableToRow persists", () => {
    const d = {
      _rowId:"uuid-d1", id:42, projectId:5,
      title:"Episode 5 Cut", status:"In Review", deadline:"2026-11-10", startDate:"2026-11-03", deliveredAt:null,
      editorId:1, animatorId:null, producerId:2,
      deliverableType:"Episode", aspectRatio:"16:9", quality:"4K",
      workstream:"BXTV", businessUnit:"MKT",
      frameLink:"https://frame.io/x", framePW:"pw123", frameInternalUrl:"https://internal/x",
      videoLength:"5:30", filePath:"/vol/x.mov",
      distPlatforms:["YouTube"], useCaseLimitations:["Internal only"], approvedUses:["Social"],
      speakers:["Jane"], keywords:["launch"], notes:"notes",
      totalRevisions:3, estimatedHoursOverride:12,
      containsAI:true, aiTools:["Runway"], greenscreen:true,
      captionsNeeded:true, srtDelivered:true, srtFrameUrl:"https://frame.io/srt",
      watermark:false, bxtvLink:"ep-6",
      srtNeeded:true, qualitiesConfirmed:true,
      _reassignmentRequested:{requestedBy:1, requestedAt:"2026-11-01T00:00:00Z", unavailabilityId:9},
    };
    const row = app.deliverableToRow(d, 5);
    expect(row.id).toBe("uuid-d1");
    expect(row.legacy_id).toBe(42);
    expect(row.project_id).toBe(5);
    const back = app.rowToDeliverable(row);
    const { rounds, ...rest } = back; // rounds is populated elsewhere, not by this mapper
    expect(rest).toEqual(d);
  });
});

describe("rowToWorkReviewSession / workReviewSessionToRow", () => {
  it("round-trips every field", () => {
    const s = { id:7, _rowId:"uuid-s1", datetime:"2026-11-05T14:00", location:"Conf Room A", zoomLink:"https://zoom/x", reviewers:["Jane","Alex"], notes:"agenda" };
    const row = app.workReviewSessionToRow(s);
    const back = app.rowToWorkReviewSession(row);
    expect(back).toEqual(s);
  });
});

describe("rowToReviewRound / reviewRoundToRow", () => {
  it("round-trips a standalone round (isWorkReview=false, reviewRoundId set)", () => {
    const r = { id:"uuid-r1", label:"Round 1", deadline:"2026-11-08", reviewers:["Jane"], status:"Pending", notes:"", workReviewSessionId:null, isWorkReview:false, reviewRoundId:555 };
    const row = app.reviewRoundToRow(r, "uuid-d1");
    expect(row.deliverable_id).toBe("uuid-d1");
    expect(row.is_work_review).toBe(false);
    expect(row.review_round_id).toBe("555");
    expect(row).not.toHaveProperty("work_review_session_id");
    const back = app.rowToReviewRound(row);
    expect(back.isWorkReview).toBe(false);
    expect(back.reviewRoundId).toBe(555); // parseLegacyId turns the numeric-looking string back into a number
    expect(back.label).toBe(r.label);
    expect(back.deadline).toBe(r.deadline);
  });

  it("round-trips a work-review round linked to a real session uuid", () => {
    const r = { id:"uuid-r2", label:"WR 1", deadline:"2026-11-09", reviewers:[], status:"Pending", notes:"", workReviewSessionId:"uuid-session-1", isWorkReview:true, reviewRoundId:null };
    const row = app.reviewRoundToRow(r, "uuid-d1");
    expect(row.is_work_review).toBe(true);
    expect(row.work_review_session_id).toBe("uuid-session-1");
    expect(row.review_round_id).toBeNull();
    const back = app.rowToReviewRound(row);
    expect(back.isWorkReview).toBe(true);
    expect(back.workReviewSessionId).toBe("uuid-session-1");
  });
});

describe("rowToProduction / productionToRow", () => {
  it("round-trips every field productionToRow persists", () => {
    const p = {
      _rowId:"uuid-p1", id:9, projectId:5,
      title:"Debrief filming", type:"Interview", location:"Studio B", startTime:"2026-08-25T09:00", endTime:"2026-08-25T17:00", booked:true,
      setupTypeId:3,
      schedule:[{day:"Mon"}], crewInternal:[{memberId:1,role:"Producer"}], crewExternal:[{name:"Ext Crew"}],
      equipmentIds:["eq-1"], externalGear:[{name:"Rented light"}], mediaCardIds:["card-1"],
      scriptFile:"script.pdf", additionalDetails:"details",
      ingest:{datetime:"2026-08-25T18:00"},
      status:"Approved", bookingStatus:"Confirmed",
      studioNote:"Studio note", rejectionNote:null,
      notes:"notes", crewCallTime:"2026-08-25T08:00",
      secondaryLocations:[{location:"HMU",type:"HMU"}], confirmations:[{crewId:1,status:"Confirmed"}],
      talent:[11], setups:[{name:"Setup A"}], deliverables:[{title:"Clip"}],
      playbackAssets:[{name:"asset"}], assetRequests:[{item:"mic"}],
      callSheet:{pdf:"callsheet.pdf"},
      feedsIntoId:123, playbackDeliverableId:456,
    };
    const row = app.productionToRow(p, 5);
    expect(row.id).toBe("uuid-p1");
    expect(row.legacy_id).toBe(9);
    const back = app.rowToProduction(row);
    expect(back).toEqual(p);
  });

  it("defaults status to Planning and bookingStatus to null when unset", () => {
    const row = app.productionToRow({ title:"New shoot" }, 5);
    const back = app.rowToProduction(row);
    expect(back.status).toBe("Planning");
    expect(back.bookingStatus).toBeNull();
  });
});

describe("rowToSetupType / setupTypeToRow", () => {
  it("round-trips every field", () => {
    const t = {
      id:1, _rowId:"uuid-t1", name:"Standard Interview", description:"desc",
      floorplanPhotoKey:"floor.jpg", refPhotoKeys:["ref1.jpg"],
      equipmentIds:["eq-1"], externalGear:[{name:"light"}],
      mediaCardIds:["card-1"], furnitureIds:[2], propIds:[3],
      recordingSpecs:{quality:"4K"}, screenContent:{type:"logo"}, notes:"notes",
      roles:["Editor"], active:true,
    };
    const row = app.setupTypeToRow(t);
    const back = app.rowToSetupType(row);
    expect(back).toEqual(t);
  });
});

describe("rowToProductionPreset / productionPresetToRow", () => {
  it("round-trips the fields productionPresetToRow persists", () => {
    const p = { id:1, _rowId:"uuid-pp1", name:"BEC Event", type:"Event", sections:{a:1}, active:true };
    const row = app.productionPresetToRow(p);
    const back = app.rowToProductionPreset(row);
    const { createdAt, ...rest } = back; // createdAt comes from the DB, productionPresetToRow doesn't write it
    expect(rest).toEqual(p);
  });
});

describe("rowToCustomTask / customTaskToRow", () => {
  it("round-trips every field", () => {
    const t = { id:"1699999999999", _rowId:"uuid-ct1", projectId:5, title:"Follow up", dueDate:"2026-11-05", reminders:[{at:"2026-11-04"}], notes:"notes", done:false };
    const row = app.customTaskToRow(t);
    const back = app.rowToCustomTask(row);
    const { createdAt, ...rest } = back;
    expect(rest).toEqual(t);
  });
});

describe("rowToGear / gearToRow", () => {
  it("round-trips every field", () => {
    const g = { id:1, _rowId:"uuid-g1", name:"Boom Mic", category:"Audio", quantity:3, notes:"notes", active:true };
    expect(app.rowToGear(app.gearToRow(g))).toEqual(g);
  });
});

describe("rowToFurniture / furnitureToRow", () => {
  it("round-trips every field", () => {
    const f = { id:1, _rowId:"uuid-f1", name:"Chair", category:"Furniture", active:true };
    expect(app.rowToFurniture(app.furnitureToRow(f))).toEqual(f);
  });
});

describe("rowToProp / propToRow", () => {
  it("round-trips every field", () => {
    const p = { id:1, _rowId:"uuid-pr1", name:"Mug", category:"Prop", active:true };
    expect(app.rowToProp(app.propToRow(p))).toEqual(p);
  });
});

describe("rowToScreenContentOption / screenContentOptionToRow", () => {
  it("round-trips every field, with category passed separately", () => {
    const item = { id:1, _rowId:"uuid-sc1", name:"Company Logo", active:true };
    const row = app.screenContentOptionToRow(item, "Logos");
    expect(row.category).toBe("Logos");
    expect(app.rowToScreenContentOption(row)).toEqual(item);
  });
});

describe("rowToUnavailability / unavailabilityToRow", () => {
  it("round-trips every field", () => {
    const u = {
      id:1, _rowId:"uuid-u1", memberId:2, type:"PTO", label:"Vacation",
      startDate:"2026-12-20", endDate:"2026-12-27", allDay:true,
      startTime:null, endTime:null, notes:"notes",
    };
    const row = app.unavailabilityToRow(u);
    const back = app.rowToUnavailability(row);
    const { createdAt, ...rest } = back;
    expect(rest).toEqual(u);
  });
});

describe("rowToTalent / talentToRow", () => {
  it("round-trips every field", () => {
    const t = { id:1, _rowId:"uuid-ta1", name:"Jamie Rivera", category:"Host", bio:"bio", photoKey:"photo.jpg", lastBookedAt:"2026-10-01", active:true };
    expect(app.rowToTalent(app.talentToRow(t))).toEqual(t);
  });
});

describe("nudgeToRow / rowToNudge (append-only, insert direction only matters)", () => {
  it("round-trips every field", () => {
    const n = { id:1, taskKey:"frame-link", projectId:5, taskId:42, taskLabel:"Add Frame link", tab:"deliverables", toMemberId:2 };
    const row = app.nudgeToRow(n);
    const back = app.rowToNudge(row);
    const { createdAt, ...rest } = back;
    expect(rest).toEqual(n);
  });
});

describe("becRequestToRow / rowToBecRequest (append-only)", () => {
  it("round-trips every field", () => {
    const b = { id:1, reservationId:"res-1", projectId:5, action:"created", receivedAt:"2026-10-01T00:00:00Z", parsed:{room:"A"} };
    const row = app.becRequestToRow(b);
    expect(app.rowToBecRequest(row)).toEqual(b);
  });
});

describe("rowToIntake / intakeToRow", () => {
  it("round-trips first-class fields and sweeps everything else into the fields jsonb blob", () => {
    const i = {
      id:1, _rowId:"uuid-i1", dateReceived:"2026-10-01", status:"New", assignedProjectId:5,
      requesterName:"Jane", requesterEmail:"jane@example.com", projectTitle:"New campaign",
    };
    const row = app.intakeToRow(i);
    expect(row.fields).toEqual({ requesterName:"Jane", requesterEmail:"jane@example.com", projectTitle:"New campaign" });
    const back = app.rowToIntake(row);
    expect(back).toEqual(i);
  });
});

describe("rowToMediaCard / mediaCardToRow", () => {
  it("round-trips every field", () => {
    const m = {
      id:1, _rowId:"uuid-mc1", label:"Card 014", category:"SSD", type:"Media Card", format:"exFAT",
      capacityGB:1000, manufacturer:"SanDisk", model:"Extreme Pro", folderName:"2026_PROJ",
      status:"In Use", assignedTo:2, projectRef:5, homeLocation:"Cage A", notes:"notes",
    };
    expect(app.rowToMediaCard(app.mediaCardToRow(m))).toEqual(m);
  });
});

describe("rowToWorkstation / workstationToRow", () => {
  it("round-trips every field", () => {
    const w = { id:1, _rowId:"uuid-ws1", name:"Edit Bay 3", location:"Floor 2", machineType:"Mac Studio", serialNumber:"SN123", assignedTo:2, available:true, active:true };
    expect(app.rowToWorkstation(app.workstationToRow(w))).toEqual(w);
  });
});

describe("rowToIngest / ingestToRow", () => {
  it("round-trips every field (seq already assigned, i.e. an existing row being updated)", () => {
    // seq itself only ever gets WRITTEN at insert time (via the separate
    // _seq field below) — an update to an already-seq'd row just carries
    // the field through rowTo/toRow unchanged, same as every other field.
    const ig = {
      id:1, _rowId:"uuid-ig1", projectId:5,
      datetime:"2026-10-20T10:00", completedAt:"2026-10-20T16:00", location:"Studio B",
      numFiles:120, totalSizeGB:45.5,
      curatorLink:"https://curator/x", transcriptNeeded:true,
      transcriptLink:"https://trint/x", trintLinks:[{url:"https://trint/x"}], mediaRows:[{card:"1"}],
      reviewLink:"https://frame.io/x", linkedReviewLinkIds:[1], reviewLinkDelIds:[2],
      mediaSource:"Camera A", notes:"notes", callSheet:{pdf:"x"}, status:"Received",
    };
    const row = app.ingestToRow(ig, 5);
    expect(row.project_id).toBe(5);
    expect(row).not.toHaveProperty("seq"); // only set when ig._seq is present (new-row assignment)
    row.seq = 3; // simulate what's already stored in the DB from the original insert
    const back = app.rowToIngest(row);
    expect(back).toEqual({ ...ig, seq: 3 });
  });

  it("writes seq only when _seq is set (new-row assignment), never overwriting an existing one", () => {
    const freshRow = app.ingestToRow({ id:2, _seq:7 }, 5);
    expect(freshRow.seq).toBe(7);
    const existingRow = app.ingestToRow({ id:3, _rowId:"uuid-ig3" }, 5);
    expect(existingRow).not.toHaveProperty("seq");
  });
});
