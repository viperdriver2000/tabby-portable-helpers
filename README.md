# tabby-portable-helpers

Two PowerShell helper scripts for [Tabby Terminal](https://github.com/Eugeny/tabby) Portable on Windows:

- **`Start-Tabby`** — launches Tabby with the correct Pageant SSH-agent pipe
- **`Update-Tabby`** — keeps Tabby up to date without touching your settings

## Why?

### The Pageant problem

Tabby ≥ 1.0.218 ships with the [russh](https://github.com/Eugeny/russh) Rust SSH library, whose Pageant transport has known bugs that produce errors like:

```
Failed to authenticate using agent: Error: IO(Custom { kind: UnexpectedEof, error: "early eof" })
Failed to authenticate using agent: Error: IO(Os { code: 2, kind: NotFound, ... })
```

See: [tabby#10174](https://github.com/Eugeny/tabby/issues/10174), [#10301](https://github.com/Eugeny/tabby/issues/10301), [#10379](https://github.com/Eugeny/tabby/issues/10379), [#10612](https://github.com/Eugeny/tabby/issues/10612), [#10896](https://github.com/Eugeny/tabby/issues/10896)

There are **three** underlying bugs:

1. The legacy `WM_COPYDATA` shared-memory transport throws `0x800703E6` (invalid memory access).
2. The newer named-pipe transport derives the pipe name via `GetUserNameExA(NameUserPrincipal)`, which **fails on non-domain-joined Windows machines** (i.e. most home / standalone setups).
3. `tokio`'s `ClientOptions::open()` returns `NotFound` even when the pipe exists.

### The workaround

Tabby supports `agentType: named-pipe` with an explicit `agentPath`. That code path uses `AgentClient::connect_named_pipe()` directly and **bypasses all three bugs**.

The catch: Pageant generates its pipe name via `CryptProtectMemory(CRYPTPROTECTMEMORY_CROSS_PROCESS)`, which produces a **different hash after every reboot or logout**. So the `agentPath` in `config.yaml` is stale the next time you log in.

`Start-Tabby.ps1` solves this by discovering the current Pageant pipe at launch time and rewriting `agentPath` in `config.yaml` before starting Tabby.

## Installation

1. Download or clone this repository.
2. Copy the four files (`Start-Tabby.ps1`, `Start-Tabby.cmd`, `Update-Tabby.ps1`, `Update-Tabby.cmd`) into your Tabby Portable directory (next to `Tabby.exe`).
3. Make sure Pageant is running with your keys loaded.
4. Double-click `Start-Tabby.cmd` instead of `Tabby.exe`.

The first time `Start-Tabby` runs it will inject the necessary `ssh:` block into `config.yaml` if it's missing — no manual configuration required.

> **Tip:** Create a desktop shortcut to `Start-Tabby.cmd` and use it as your only Tabby launcher.

## Scripts

### Start-Tabby

```powershell
.\Start-Tabby.ps1            # update agentPath, start Tabby
.\Start-Tabby.ps1 -OnlyUpdate # update only, do not launch
```

What it does:

1. Lists Windows named pipes and finds the one matching `^pageant\.`.
2. Reads `data/config.yaml`.
3. Updates `agentPath` (handles single-quoted, double-quoted, and folded `>-` YAML formats).
4. If `agentType: named-pipe` is missing, inserts it.
5. If the entire `ssh:` block is missing, creates it.
6. Launches `Tabby.exe` (skips if already running).

If Pageant is not running, the config is left untouched and Tabby is launched anyway.

### Update-Tabby

```powershell
.\Update-Tabby.ps1           # update to latest version
.\Update-Tabby.ps1 -Check    # only check, do not install
.\Update-Tabby.ps1 -Force    # re-install even if already up to date
```

What it does:

1. Reads the local Tabby version from `Tabby.exe`'s file metadata.
2. Queries the GitHub Releases API for the latest version.
3. Downloads `tabby-<version>-portable-x64.zip` to `%TEMP%`.
4. Extracts the archive.
5. Stops any running Tabby processes.
6. Replaces the program files but **leaves `data/` untouched** (your config, profiles, plugins are preserved).
7. Verifies the new version.

## Requirements

- Windows 10 / 11
- Tabby Portable (x64) — install from <https://github.com/Eugeny/tabby/releases>
- PuTTY's Pageant ≥ 0.75 (for the named-pipe transport)
- PowerShell 5.1+ (built into Windows)

## Why double-click `.cmd` instead of `.ps1`?

By default Windows blocks running `.ps1` scripts (Execution Policy). The `.cmd` wrappers call PowerShell with `-ExecutionPolicy Bypass` for that single invocation, so it works without changing system-wide policy.

## Cleaning up

If you ever want to revert: delete the four script files and remove the `agentPath` line from `data/config.yaml` (or set `agentType: pageant` to use Tabby's default — broken — Pageant code path).

## License

MIT
