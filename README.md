# homebrew-tap

Homebrew tap for third-party macOS casks that are not maintained in official Homebrew repositories.

Current casks:
- `dynamicnotch`
- `notepad-plus-plus-macos`

Repository:
- `https://github.com/hordesnake1/homebrew-tap`

## Install tap

```bash
brew tap hordesnake1/local https://github.com/hordesnake1/homebrew-tap
```

For local development:

```bash
brew tap hordesnake1/local /Users/dyakovlev/homebrew-tap
```

## Install apps

```bash
brew install --cask dynamicnotch
brew install --cask notepad-plus-plus-macos
```

## Upgrade apps

Standard Homebrew flow:

```bash
brew update
brew upgrade --cask dynamicnotch
brew upgrade --cask notepad-plus-plus-macos
```

If `brew-cask-upgrade` is installed:

```bash
brew cu -a -f
```

## Auto-update model

Each cask has its own updater script and GitHub Actions workflow.

- `dynamicnotch`:
  - updater: `bin/update-dynamicnotch`
  - workflow: `.github/workflows/update-dynamicnotch.yml`
- `notepad-plus-plus-macos`:
  - updater: `bin/update-notepad-plus-plus-macos`
  - workflow: `.github/workflows/update-notepad-plus-plus-macos.yml`

Each workflow:
1. checks the upstream GitHub release API on a schedule,
2. rewrites the local cask file if a new release exists,
3. commits and pushes the change back to this tap repository.

Once the cask file is bumped in the tap, `brew update` and `brew upgrade` on the client machine pick up the new version.

## Manual bump

```bash
/Users/dyakovlev/homebrew-tap/bin/update-dynamicnotch
/Users/dyakovlev/homebrew-tap/bin/update-notepad-plus-plus-macos
```

Then:

```bash
cd /Users/dyakovlev/homebrew-tap
git add Casks/
git commit -m "chore(cask): bump versions"
git push
```

## Notes

- Casks use `sha256 :no_check` because the upstream asset URL is versioned and this tap is intended for fast-moving third-party releases.
- `livecheck` is configured in each cask, so Homebrew can report the currently known upstream version.
- GitHub Actions must be enabled for this repository, and workflow permissions must allow `contents: write`.

## Agent runbook

For full reproducible deployment instructions for another machine or another repository, see:

- `AGENT-RUNBOOK.md`

## Additional archived operator docs

Operational Telegram proxy notes copied from the local workspace are stored under:

- `docs/telegram-proxy/README.md`
