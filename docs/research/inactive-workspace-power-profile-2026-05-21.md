# Inactive Workspace Power Profile Summary (2026-05-21)

## Executive summary

This note summarizes six manual runtime power-profile captures taken for the OpenSpec change [`optimize-inactive-workspace-power`](../../openspec/changes/optimize-inactive-workspace-power/proposal.md). The runs were collected with the scripted capture flow added during that change, using the same machine, same branch name, and the same manual interaction schema before and after rebuilding the app with the inactive-surface visibility fixes.

The strongest result is that the **post-fix app consistently showed lower final CPU, fewer threads, and sharply reduced CVDisplayLink / Metal / QuartzCore activity** across visible, hidden, and minimized scenarios. Memory stayed roughly flat, which is acceptable because the change targeted presentation and display work, not steady-state resident size.

The evidence is manual and therefore somewhat noisy, but the direction is consistent enough to treat the fix as materially successful for the intended goal: **reduce non-visible rendering/display work without suspending inactive workspace sessions**.

## OpenSpec context

- Change: [`optimize-inactive-workspace-power`](../../openspec/changes/optimize-inactive-workspace-power/proposal.md)
- Design: [`openspec/changes/optimize-inactive-workspace-power/design.md`](../../openspec/changes/optimize-inactive-workspace-power/design.md)
- Tasks: [`openspec/changes/optimize-inactive-workspace-power/tasks.md`](../../openspec/changes/optimize-inactive-workspace-power/tasks.md)

The change goals most relevant to this note were:

- keep inactive workspace sessions live
- hide or occlude non-visible terminal surfaces
- reduce renderer/display-link activity for hidden surfaces
- compare before/after CPU, memory, thread count, and sampled renderer activity using repeatable local macOS tools

## Capture method

The runs were captured with `Scripts/capture-openmux-power-profile.sh`, which records:

- branch and commit metadata
- periodic `ps` snapshots for CPU, RSS, and thread count
- final `ps`, `top`, `sample`, and `vmmap` artifacts
- a derived signal summary from the final `sample` output

The manual workflow exercised:

- workspace switching
- inactive workspaces
- Markdown Preview modal/open-close flow
- Agent Sessions sidebar
- tab movement / repositioning
- theme switching
- Helix in one workspace
- a live `pnpm dev` workload in another workspace
- visible, hidden, and minimized end states

The `main-` label prefix was used for **before-fix** runs. The matching runs without that prefix are the **after-fix** runs.

## Runs compared

### After-fix

- `20260521-131157-feat-optimize-n-power-saving-manual-mixed-workflow`
- `20260521-131714-feat-optimize-n-power-saving-manual-mixed-workflow-hidden`
- `20260521-132200-feat-optimize-n-power-saving-manual-mixed-workflow-minimized`

### Before-fix

- `20260521-132928-feat-optimize-n-power-saving-main-manual-mixed-workflow`
- `20260521-133310-feat-optimize-n-power-saving-main-manual-mixed-workflow-hidden`
- `20260521-133617-feat-optimize-n-power-saving-main-manual-mixed-workflow-minimized`

## Before/after comparison

| Scenario | Before final CPU | After final CPU | Before final threads | After final threads | Before CVDisplayLink | After CVDisplayLink | Before Metal queue submits | After Metal queue submits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Visible | 5.8 | 1.8 | 77 | 71 | 44 | 5 | 27 | 5 |
| Hidden | 8.1 | 1.6 | 77 | 71 | 34 | 5 | 24 | 3 |
| Minimized | 7.6 | 1.9 | 77 | 71 | 44 | 6 | 30 | 4 |

## Detailed summary

### Visible end state

- final CPU dropped from **5.8** to **1.8**
- final threads dropped from **77** to **71**
- CVDisplayLink hits dropped from **44** to **5**
- QuartzCore commits dropped from **21** to **0**
- Metal queue submits dropped from **27** to **5**

Interpretation: the app remained active and visible, but non-essential renderer/display activity still fell sharply after the fix.

### Hidden end state

- final CPU dropped from **8.1** to **1.6**
- final threads dropped from **77** to **71**
- CVDisplayLink hits dropped from **34** to **5**
- QuartzCore commits stayed at **4**
- Metal queue submits dropped from **24** to **3**

Interpretation: hiding the app no longer leaves the previous level of display-link and GPU queue activity running. This is consistent with the intended hidden-surface quiescing behavior.

### Minimized end state

- final CPU dropped from **7.6** to **1.9**
- final threads dropped from **77** to **71**
- CVDisplayLink hits dropped from **44** to **6**
- QuartzCore commits dropped from **34** to **2**
- Metal queue submits dropped from **30** to **4**
- IOSurface hits dropped from **4** to **2**

Interpretation: this was the clearest result of the three scenario pairs. The minimized-window case showed the strongest reduction in renderer/display-path activity.

## Memory observations

Resident memory was broadly similar before and after:

- visible: `336240 KB` before vs `346432 KB` after
- hidden: `338976 KB` before vs `333936 KB` after
- minimized: `337504 KB` before vs `337744 KB` after

This change was not expected to be a large RSS reduction. Stable memory with significantly lower renderer/display activity is an acceptable outcome.

## Remaining activity

The post-fix samples still show some renderer-related work, but at a much lower level. The remaining visible signals appear to fall into two buckets:

1. **Expected visible-surface work** when the app is frontmost and one workspace remains visible.
2. **Unrelated or secondary background work**, especially icon-refresh and terminal-text inspection paths that still show up in samples even after hidden-surface rendering was reduced.

This matches the earlier observation that some remaining idle cost now appears to involve:

- `WorkspaceShellViewController.refreshTerminalAppIconsIfNeeded()`
- `GhosttyTerminalBridge.terminalTextSnapshot(...)`

rather than only the hidden-surface rendering path that motivated the original change.

## Caveats

- The runs were manual, not hardware-lab grade.
- The interaction sequence was intentionally consistent, but still subject to human timing differences.
- Peak CPU values remain noisy and should be treated as secondary compared with the final-idle values and sampled renderer/display signals.
- The six runs were captured from the same branch name because the capture script lived there; the meaningful distinction is the app build used for the `main-` labeled runs versus the rebuilt fixed runs.

## Conclusion

These six runs are sufficient to support the claim that the `optimize-inactive-workspace-power` change improved runtime behavior in the intended direction.

The most important outcomes are:

- **final CPU decreased materially**
- **thread count decreased consistently**
- **CVDisplayLink activity dropped sharply**
- **Metal queue submission activity dropped sharply**
- **QuartzCore commit activity dropped sharply in the visible and minimized cases**

The data supports classifying the remaining activity as:

- mostly **expected visible-surface work** for the active workspace
- some **secondary background work** still worth future investigation
- substantially less evidence of the original **hidden-surface renderer/display churn**

## Recommended follow-up

If follow-up work is needed, the next likely target is not the hidden-surface occlusion path itself, but the remaining periodic shell-side inspection work visible in samples, especially:

- terminal icon refresh
- terminal text snapshot reads used for shell metadata/icon derivation

Those are better candidates for a separate optimization change than for extending the current visibility fix further.
