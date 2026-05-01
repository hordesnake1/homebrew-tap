# AI Agent Runbook: Recreate This Homebrew Tap On Another Machine

This document describes exactly how this tap was built so another agent can reproduce it on a different Mac or GitHub account.

## Goal

Create a Homebrew tap that:
1. hosts custom casks for third-party macOS apps,
2. tracks upstream GitHub releases automatically,
3. updates cask files via GitHub Actions,
4. allows client machines to update apps through normal Homebrew commands.

## Current reference implementation

Repository:
- `https://github.com/hordesnake1/homebrew-tap`

Implemented casks:
- `dynamicnotch`
- `notepad-plus-plus-macos`

## Preconditions

On the build machine you need:
- macOS
- Homebrew installed
- Git installed
- GitHub CLI (`gh`) installed
- a GitHub account authenticated in `gh`

Recommended checks:

```bash
brew --version
git --version
gh --version
gh auth status
```

If `gh auth status` is not authenticated:

```bash
gh auth login --web --clipboard --git-protocol ssh --skip-ssh-key
```

## Step 1: Create local tap repository

Pick a working directory, for example:

```bash
mkdir -p ~/homebrew-tap
cd ~/homebrew-tap
git init
git branch -M main
```

Create structure:

```bash
mkdir -p Casks
mkdir -p bin
mkdir -p .github/workflows
```

## Step 2: Create a cask

Each app needs one file under `Casks/`.

Pattern:

```ruby
cask "example-app" do
  version "1.2.3"
  sha256 :no_check

  url "https://github.com/vendor/project/releases/download/v#{version}/ExampleApp-v#{version}.dmg"
  name "Example App"
  desc "Short description"
  homepage "https://github.com/vendor/project"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Example App.app"
end
```

Reference files in this repository:
- `Casks/dynamicnotch.rb`
- `Casks/notepad-plus-plus-macos.rb`

## Step 3: Create an updater script per app

Each app needs one updater script in `bin/`.

Responsibilities of the script:
1. call GitHub Releases API,
2. extract latest tag,
3. find the correct `.dmg` asset,
4. rewrite the matching cask file.

Required implementation details:
- use `curl` with GitHub API headers,
- pass `Authorization: Bearer ${GITHUB_TOKEN}` if available,
- fail if expected DMG asset is not found.

Reference scripts:
- `bin/update-dynamicnotch`
- `bin/update-notepad-plus-plus-macos`

## Step 4: Create GitHub Actions workflow per app

Each app needs one workflow in `.github/workflows/`.

Pattern:

```yaml
name: Update Example App cask

on:
  workflow_dispatch:
  schedule:
    - cron: '17 */6 * * *'

jobs:
  update:
    runs-on: macos-latest
    permissions:
      contents: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Update cask from upstream release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: ./bin/update-example-app

      - name: Commit changes
        run: |
          if git diff --quiet; then
            echo "No changes"
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Casks/example-app.rb
          git commit -m "chore(example-app): bump cask"
          git push
```

Reference workflows:
- `.github/workflows/update-dynamicnotch.yml`
- `.github/workflows/update-notepad-plus-plus-macos.yml`

## Step 5: Commit local repository

```bash
git add .
git commit -m "feat(tap): initial casks and update workflows"
```

## Step 6: Create GitHub repository and push

If creating a new remote repository through `gh`:

```bash
gh repo create <github-user>/homebrew-tap --public --source=. --remote=origin --push --description "Homebrew tap for third-party casks"
```

If the remote already exists:

```bash
git remote add origin git@github.com:<github-user>/homebrew-tap.git
git push -u origin main
```

## Step 7: Enable and verify Actions

Open the repository in GitHub and verify that Actions are enabled.

Then run each workflow manually once:
- `Update DynamicNotch cask`
- `Update Notepad++ macOS cask`

Expected successful behavior:
- workflow exits green,
- if no upstream update exists, commit step prints `No changes`,
- if an update exists, a commit is pushed automatically.

Common failure:
- `curl` to GitHub API returns `403`

Fix:
- ensure the updater script sends GitHub API headers,
- ensure the workflow exports `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}`.

## Step 8: Attach the tap on the client machine

On any Mac that should consume the tap:

```bash
brew tap <github-user>/local https://github.com/<github-user>/homebrew-tap
```

Then install apps:

```bash
brew install --cask dynamicnotch
brew install --cask notepad-plus-plus-macos
```

## Step 9: Normal update flow on the client machine

```bash
brew update
brew upgrade --cask dynamicnotch
brew upgrade --cask notepad-plus-plus-macos
```

If `brew-cask-upgrade` is installed:

```bash
brew cu -a -f
```

## How to add another app

To add another GitHub-distributed app:
1. inspect latest release asset name,
2. create `Casks/<app>.rb`,
3. create `bin/update-<app>`,
4. create `.github/workflows/update-<app>.yml`,
5. commit and push,
6. manually run the workflow once,
7. verify `brew info --cask <app>` and `brew livecheck <app>`.

## Commands used for verification

Server-side / tap-side:

```bash
gh auth status
gh run list --repo <github-user>/homebrew-tap
gh run view <run-id> --repo <github-user>/homebrew-tap --log-failed
```

Client-side:

```bash
brew info --cask <cask>
brew livecheck <cask>
brew list --cask
```

## Known caveats

- `sha256 :no_check` trades strict integrity pinning for easier maintenance.
- If a GitHub release changes asset naming conventions, the updater regex must be adjusted.
- Homebrew tap clones under `/opt/homebrew/Library/Taps/...` may lag behind if manually edited; if needed, reset the tap clone to `origin/main`.
- Existing manually copied `.app` bundles in `/Applications` can block initial `brew install --cask`; move or delete the manual app before installing through Homebrew.
