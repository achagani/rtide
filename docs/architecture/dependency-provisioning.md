# Dependency provisioning

RTIDE depends on external host tools (tmux, Neovim, TWeb, an agent harness, a
terminal, and optional voice tooling). Installation and diagnostics must agree
about which of those block RTIDE, which only matter for an optional source
build, and which merely degrade a capability.

## One matrix

`libexec/rtide/deps` is the single source of truth. Each requirement declares:

- `name`, `category`, and `level` — `required`, `build`, or `optional`;
- how it is detected — a `commands` list, or a `kind` (`pkgconfig`, `lazyvim`,
  `speech`) with the capability it needs;
- the host `packages` for each supported manager (`apt-get`, `dnf`, `brew`,
  `pacman`, `zypper`), or a `provisioned` installer script;
- a `remedy` string used verbatim in actionable failures.

`required` and `build` entries are blockers. `build` tools (Cargo, pkg-config,
and GTK/WebKit development libraries) only block when TWeb itself is missing and
would have to be built from source. `optional` entries are warnings and never
make `rtide doctor` fail.

## Consumers

- `rtide doctor` renders the matrix, separating `MISSING` blockers from
  `WARN (optional)` capabilities and printing the remedy for each blocker. It
  reports build tools as informational when TWeb is already present.
- `scripts/install-deps` asks the matrix for the packages missing under the
  detected manager and installs exactly those, so it can never provision an
  already-satisfied or optional-only tool.
- `scripts/install-tweb` and `scripts/install-lazyvim` remain the provisioners
  referenced by `provisioned`.

## Boundaries

- Package-manager staging (`make stage`) performs no installation and no host
  mutation; it only assembles the payload.
- Unsupported platforms are reported, not hidden: with no recognized package
  manager the installer stops with the explicit missing list.
- Adding a requirement means editing only the matrix; doctor, installer package
  selection, and tests follow from that single definition.
