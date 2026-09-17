# Runtime settings

RTIDE separates configuration a user wants from configuration the running
workspace has proved it is using. This prevents a persisted permission change
from being reported as a successful security transition when no agent process
changed.

## State layers and precedence

The settings schema lives in `libexec/rtide/settings`. Resolution proceeds from
built-in defaults, to `~/.rtide/config` (or `RTIDE_CONFIG_DIR/config`), to the
workspace's `.rtide/agent` overrides. Those layers are desired state only.
`.rtide/effective-settings.json` is a separate runtime record written by the
launcher and by the running agent wrapper.

Config files use a deliberately small `key=value` data format. They are parsed
without shell evaluation. Atomic updates replace known keys while preserving
comments, unknown keys, and unrelated values, allowing newer settings to survive
edits by older commands.

## Apply classes

| Class | Contract |
| --- | --- |
| `immediate` | Applied to the active tmux layout by the explicit apply action. |
| `next-turn` | Applied by a controlled agent-wrapper restart before another tool call; success requires a new PID to publish matching effective state. |
| `next-operation` | Read by the next operation that uses the setting. |
| `restart-required` | Persisted as desired state and shown as pending until a workspace restart publishes it as effective. |
| `explicit-only` | Stored as a preference but deliberately never applied automatically; the user performs the action explicitly. |

`auto_float` is the current `explicit-only` setting: the RTIDE convention forbids
floating output during an agent turn, so the preference is retained but reported
as `explicit-only` rather than a pending or effective runtime value.

`rtide settings status` displays scope, apply class, desired value, effective
value, and convergence state for every startup-configurable setting. `set` only
persists desired state. `apply` is the explicit transition boundary.
`rtide settings edit` is the in-session surface: it lists the same state, then
persists and applies or defers each change according to its class. Global-only
keys are written to the global config; `global+workspace` keys are written as
workspace overrides.

## Config parsing

`~/.rtide/config` and `.rtide/agent` are parsed as data by `load_config_file`,
never sourced. Known keys are read; unknown keys, comments, and unrelated values
are preserved by atomic updates. A partial or hand-edited config degrades to
schema defaults instead of aborting the command or launch.

## Agent transitions

Agent panes are discovered without parsing tmux delimiter escapes. RTIDE asks
tmux to filter panes by `@rtide-role=agent`, then queries each candidate's path
separately and compares canonical paths. This avoids the former mismatch between
literal `\t` output and an `awk` real-tab delimiter.

For provider, harness, model, or permission changes, RTIDE interrupts the wrapper
and starts a replacement in the same pane. Conversation session identifiers and
workspace artifacts remain on disk and are resumed when the harness supports it.
The replacement publishes its PID and active arguments atomically. RTIDE reports
success only after the PID changes and all requested values match. On timeout it
restores desired agent values from the last effective record and restarts the
previous configuration; the failed desired state is never presented as effective.

## Permission capabilities

Policies have concrete meanings: `workspace` requests workspace-write isolation,
`observe` requests read-only isolation, `native` delegates to the harness without
an RTIDE sandbox claim, and `unrestricted` requests host-level access. Broader
access requires the exact `UNRESTRICTED` confirmation.

Codex currently enforces all four policies for new and resumed turns. New turns
pass the policy with `--sandbox`; resumed turns cannot, because `codex exec
resume` rejects that flag, so the same policy is passed as a config override
(`-c sandbox_mode="…"`). `unrestricted` resume keeps the bypass flag and `native`
resume adds nothing. Claude, Hermes, and OpenCode are declared `native` only
because their current RTIDE invocations do not provide equivalent enforceable
sandbox controls. Unsupported policies are rejected before desired state changes
and can never be published as
effective by a settings transition.

## Security boundaries

- The harness remains the enforcement boundary; RTIDE does not claim stronger
  isolation than the command it launches.
- Effective state is process-published evidence, not a copy of desired config.
- Elevation is explicit and typed; de-escalation is verified by the same process
  transition contract.
- Failed transitions retain workspace files, output history, and resumable harness
  session state while restoring the last effective agent configuration.
