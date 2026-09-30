# ZSH-015: npm search shows keywords as the available version and drops keyword-less matches

| Field | Value |
| --- | --- |
| Status | Open |
| Priority | P2 |
| Audit date | 2026-09-30 |
| Audited baseline | `453cf43` |
| Affected surface | `upkg search` with npm; `_upkg_run_search_npm` |
| Evidence | Reproduced against native npm 11.19.1 on this host, end-to-end through the repository function |

## Summary

`_upkg_run_search_npm` reads the available version from field 5 of the `npm search --parseable` line. Current npm emits five fields — name, description, date, version, keywords — so field 5 is the keywords column and the version is field 4. Every result therefore displays its keywords as the available version, and a newly added non-empty gate discards each match whose keywords are empty.

## Affected code and documentation

- [lib/functions-upkg-backends.zsh](../../lib/functions-upkg-backends.zsh): `_upkg_run_search_npm` — the field assignment `name=$fields[1]; description=$fields[2]; version=$fields[5]` and the accompanying `-n $version` row gate.
- [scripts/test-upkg.zsh](../../scripts/test-upkg.zsh): the npm `search --parseable` fixtures, which emit six columns including an author field that current npm no longer prints.
- [GUIDE.md](../../GUIDE.md): npm search results and the available-version column.

## Trigger and reproduction

Native shape, with npm 11 or newer and network access to the registry:

1. `npm search --parseable --json=false --color=false -- express`
2. Inspect the tab-separated fields. Observed: `express`, description, `2025-12-01`, `5.2.1`, `express,framework,sinatra,web,http,rest,restful,router,app,api` — five fields, version at position 4.
3. Count rows whose field 5 is empty. Observed: 6 of 20 rows, including `@types/express`, which carries version `5.0.6` in field 4.

Repository behavior, in a fresh `zsh -f` shell at the repository root:

1. `source init.zsh`, then load the package domain.
2. Run `_upkg_run_search_npm express` and inspect `_UPKG_SEARCH_ROWS`.

Observed at the baseline: 14 rows returned, each displaying keywords in the available-version column, and the 6 keyword-less rows absent. Expected: 20 rows with the real versions.

## Current behavior and impact

The available-version column of `upkg search` is populated with keywords for every npm result, so the column is unusable and can mislead a user comparing candidate versions. Matches without keywords — common for scoped and infrastructure packages — are dropped from the result set entirely while the command still reports a successful search, so a user sees an incomplete inventory with no indication that anything was filtered. A query whose matches all lack keywords reports `no matches` with status 0 even though npm returned results.

## Root cause

The parser encodes a historical column layout. Older npm printed an author column between the description and the date, making the version field 5; current npm omits it. The fixtures were written against the older layout, so the suite cannot observe the drift, and the non-empty gate then converts the empty-field case from a display bug into silent data loss.

## Fix goal and expected behavior

Parse the current `npm search --parseable` layout, taking the version from field 4 and treating keywords as unused. Rows must not be discarded because an unrelated column is empty. If a future npm layout change removes the version field, the backend must degrade to an explicit unknown or a visible diagnostic rather than silently dropping matches or promoting another column.

### Review comment — 2026-09-30

**Assessment:** Confirmed defect; the proposed fixed column is insufficient.

**Evidence:** The installed npm 11.19.1 formatter emits name, description, date, version, and keywords for the ordinary case. The backend currently treats keywords as the version and drops keyword-less matches. A fixture reproduced both failures.

**Reviewed scope and expected behavior:** The native formatter also applies `.filter(Boolean)`: an empty description disappears, producing four fields with version in field 3. Simply choosing field 4 while keeping a five-field minimum still loses legitimate results. Support the actual supported npm layouts or use a stable structured schema; test empty descriptions as well as empty keywords. See the [npm 11.19.1 formatter source](https://raw.githubusercontent.com/npm/cli/v11.19.1/lib/utils/format-search-stream.js).

This comment reviews baseline `453cf43`; it does not implement a fix. Revise any conflicting original acceptance criteria to match the reviewed scope before repair.

## Implementation constraints

- Keep the existing field-count floor so malformed or truncated lines are still rejected.
- Keep the scoped-name pattern validation for `@scope/name` packages.
- Preserve the documented no-match and failure conventions and the stderr separation for successful-command warnings.
- Do not add a dependency on the npm JSON output format.
- Update the npm search fixtures in `scripts/test-upkg.zsh` to emit the current five-column line, and keep at least one row with an empty trailing field to lock in the no-drop behavior.

## Acceptance criteria

- [ ] The available-version column contains the real version for every npm-derived row.
- [ ] Keyword-less matches are retained rather than dropped.
- [ ] Row count equals the number of valid native records.
- [ ] Malformed or short lines are still rejected without aborting the search.
- [ ] The updated fixture fails against the audited field mapping.
- [ ] A query with only keyword-less matches does not report a false `no matches`.

## Validation plan

Update the npm fixtures in `scripts/test-upkg.zsh` to the five-column layout, add a keyword-less row, and assert the parsed row contents and count. Keep the existing no-match and error cases. Run `zsh scripts/run-tests.zsh`. Optionally re-verify the field layout with `npm search --parseable` on a host with network access.

## References

- [npm search documentation](https://docs.npmjs.com/cli/v11/commands/npm-search/)
- [GUIDE.md](../../GUIDE.md) package backend notes
- Related: [ZSH-014](014-dnf-quiet-no-match-misclassified.md)
