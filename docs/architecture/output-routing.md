# Output routing and connection recovery

RTIDE routes every artifact to one registered browser pane in the workspace's tmux
window. Submission of a navigation and visible acknowledgement of that navigation
are different facts; the routing layer must never conflate them.

## States

`libexec/rtide/tweb-common.sh` classifies the workspace output connection as one
of the following. `rtide tweb status` prints the current state with a short detail.

| State | Meaning |
| --- | --- |
| `connected` | The registered pane exists and `tweb` reports a running browser in it. |
| `disconnected` | The registered pane still exists, but no browser is running in it. |
| `missing` | The registered pane is gone, or the workspace has no registered pane. |
| `multiple` | More than one `@rtide-role=tweb` pane exists, which is a configuration error. |
| `standalone` | No RTIDE workspace context; ordinary `tweb open` behavior applies. |

`queued` is tracked separately: a `.rtide/render-request` newer than the recorded
`last-render` marker means an artifact is waiting for the workspace controller.

## Lifecycle

1. **Locate.** `rtide_tweb_prepare` resolves the pane from a harness hint, the
   current pane, or the workspace's `.rtide/tweb-pane` registration.
2. **Classify.** The pane is probed with tmux (pane liveness) and `tweb status`
   (browser liveness) before any display claim.
3. **Submit.** In a `connected` pane, `tweb navigate` submits the target. In a
   `disconnected` pane, RTIDE reconnects in place with a single `tweb open` in the
   existing pane. In `missing`/`multiple`, it does not guess.
4. **Acknowledge.** RTIDE polls `tweb status` until the target URL is the active
   tab, with a bounded wait. Success is only reported after acknowledgement.
5. **Preserve.** If the pane cannot be recovered automatically, the target is
   written to `.rtide/render-request` so the workspace controller can replay it.

## Recovery boundaries

- **Reconnect** (`rtide tweb recover`) reuses the registered pane. If the pane is
  live but browserless, it launches exactly one browser there. If the registration
  is stale but the window has exactly one role pane, the registration is rewritten.
- **Recreate** (`rtide tweb recreate`) is the explicit safe path for a truly
  missing pane. It is never invoked during an agent turn. It creates at most one
  `@rtide-role=tweb` pane, refuses when one already exists, and keeps the recorded
  last-render target so the recovered pane shows the current artifact.
- **Never duplicate.** The guard wrapper continues to route `tweb split`/`open`
  from an agent to the registered pane, and recreation refuses a duplicate role.

## Honesty contract

`rtide render` returns success only when the navigation was submitted to a live
pane; its message distinguishes `rendered` (acknowledged), `submitted … awaiting
acknowledgement`, and `queued`. It never prints "displayed" for a queued or merely
submitted target. The agent controller re-verifies the active URL before marking a
turn complete and reports "tweb could not verify the result page" otherwise.
