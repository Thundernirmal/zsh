# ZSH-025: The issue tracker's standing pages restate maintenance rules owned elsewhere

| Field | Value |
| --- | --- |
| Status | Open; reclassified during filing — see The status of the original symptom |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | README documentation index; `docs/issues/README.md` |
| Evidence | Established by source inspection of the merged tree |

## Summary

At the audited baseline, `docs/issues/` contained no reports — every finding it was created to track had been fixed and deleted within the same branch — while `README.md` still described the directory as holding open findings, reproduction details, and acceptance criteria. Filing this audit repopulates the directory, so the index entry becomes accurate again; that symptom is recorded here because it has a lifecycle rather than being a one-off. The README entry and the tracker pages are written as though the directory always contains findings, while the repository's own rule is to delete a report once it is fixed, so any period between the last fix and the next audit re-creates the mismatch. What remains after filing is the standing content of the tracker's own pages: they restate the repair loop and maintenance policy that AGENTS.md already owns, creating a second contract that must be kept in sync.

## Affected code and documentation

- [README.md](../../README.md): the documentation entry describing `docs/issues/README.md` as holding open audit findings, reproduction details, and fix acceptance criteria.
- [docs/issues/README.md](README.md): the report-structure, reproducing-and-validating, and maintenance sections.
- [AGENTS.md](../../AGENTS.md): the documentation ownership rules, including the requirement to remove stale documents and their links instead of maintaining duplicate historical status notes, and to link between surfaces instead of copying long explanations.

## Trigger and reproduction

1. Inspect the merged tree at the audited baseline: `docs/issues/` contains only `README.md` and `TEMPLATE.md`, and the tracker page states that there are no open reports.
2. Read the README documentation entry pointing at that page.
3. Compare the tracker's "Reproducing and validating findings" and "Maintenance" sections with the verification and documentation rules in AGENTS.md.

Observed: the README entry describes content that was absent, and the repair loop, verification commands, and maintenance policy appear in both the tracker page and AGENTS.md.

## Current behavior and impact

A reader following the entrypoint's documentation index can land on a page whose only content is a statement that it is empty, and cannot tell whether the project has no known defects or the page is simply unused. Separately, the repair procedure now has two owners, so a change to the verification or documentation rules must be applied twice or the surfaces disagree — the duplication the repository's documentation rules prohibit.

## Root cause

The tracker was added as a permanent documentation surface with standing prose, while the reports it indexes are transient by design. The index entry assumed the populated state, and the process guidance was placed with the reports rather than with the repository's maintenance rules.

## Fix goal and expected behavior

The README entry must be accurate whether or not reports are present — by describing the directory's purpose rather than asserting its contents, or by being added and removed with the reports. The repair loop, verification commands, and maintenance policy must have exactly one owner, with the other surface linking to it. Adding or removing a report must not require editing stale status sentences.

### Review comment — 2026-09-30

**Assessment:** Documentation improvement only; several supporting claims are incorrect.

**Evidence:** At HEAD the tracker explicitly says there are no open reports, and also contains a template, report structure, validation guidance, and maintenance guidance. Thus its content is not only an unexplained empty-page statement. README’s label describes the linked tracker’s purpose.

**Reviewed scope and expected behavior:** AGENTS.md owns general verification and maintenance rules, but it does not specify the user-requested fix/commit/subagent-review loop. The assertion that this loop is duplicated in AGENTS.md is false. Shorten duplicate general guidance by linking to AGENTS.md if useful, and make the index label explicitly purpose-based; do not treat an empty, clearly labelled tracker as an established correctness defect or remove guidance unique to the user’s requested workflow.

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the documentation ownership boundaries: README is the short entrypoint, GUIDE is the user reference, AGENTS.md owns maintenance and verification rules.
- Keep the tracker usable as a working surface for the repair loop described in AGENTS.md.
- Do not remove the per-report structure defined by `TEMPLATE.md`; the ten sections are the report contract.
- Keep the change limited to documentation; no behavioral module changes.

## Acceptance criteria

- [ ] The README entry is accurate when `docs/issues/` contains reports and when it contains none.
- [ ] The repair loop, verification commands, and maintenance policy exist in exactly one owning surface, with the other linking to it.
- [ ] A reader following the documentation index reaches content that is accurate at the merged commit.
- [ ] Adding or fixing a report requires no edit to standing status prose.
- [ ] `TEMPLATE.md` continues to define the report structure.

## Validation plan

Review the merged tree's README documentation list, the tracker's standing pages, and AGENTS.md together, and confirm each rule has a single owner and each link resolves to accurate content in both the populated and empty states. No test suite covers documentation surfaces; verification is by inspection.

## References

- [AGENTS.md](../../AGENTS.md) documentation ownership and stale-document rules
- [README.md](../../README.md)
- [TEMPLATE.md](TEMPLATE.md)
- Related: [ZSH-026](026-guide-optional-integration-table-missing-checkupdates.md)
