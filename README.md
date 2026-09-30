# Unity CI/CD with the Unity CLI

A small, copyable GitHub Actions setup that tests and builds a Unity project with the official Unity CLI (`unity`): it installs the Editor, activates a license, runs `unity test` and `unity run`, validates the player, and uploads it. The repository is also a minimal Unity project that the workflows build and test: one scene, one EditMode test, and one build entry point.

No Unity step uses GameCI or a Docker image. Every Unity step is a plain `unity` command that you can run on your own machine.

## Contents

| Path | What it does |
|---|---|
| `.github/workflows/test.yaml` | Runs the EditMode tests with `unity test`, annotates failing tests, writes a job summary and uploads the NUnit XML and the Editor log. |
| `.github/workflows/build.yaml` | Builds every profile in `build_profiles.json` with `unity run -executeMethod CIHelper.Build`, validates WebGL output, uploads each player as an artifact, and can deploy a WebGL player to GitHub Pages. |
| `.github/workflows/build_profiles.json` | The build matrix: one entry per player you build. |
| `.github/workflows/cache_warm.yaml` | Imports the project once per cache lane and saves the `Library` folder, on demand and weekly. |
| `.github/workflows/check_scripts.yaml` | Runs the shell fixture tests, `shellcheck` and `actionlint` when anything under `.github/` changes. |
| `.github/actions/setup-unity` | Installs the pinned Unity CLI and the Editor from `ProjectSettings/ProjectVersion.txt` with its modules, and activates a license. |
| `.github/actions/teardown-unity` | Returns the license, but only if this job activated it. |
| `.github/actions/library-cache` | Restores and saves `Library` under one shared key scheme. |
| `.github/actions/restore-git-lfs` | Pulls Git LFS objects before Unity imports anything, with a cache on GitHub-hosted runners. |
| `.github/actions/free-disk-space` | Frees space on GitHub-hosted runners, then fails early on any runner that is still short. |
| `.github/scripts/` | The license, annotation, test-summary, WebGL-payload and module-repair scripts, each with a `test_*.sh` fixture test. |
| `Assets/Editor/CIHelper.cs` | The build entry point. It builds the enabled scenes for the active build target. |
| `Assets/Editor/WebGLBuildOutputValidator.cs` | The C# half of the WebGL payload contract. |
| `Assets/Tests/Editor/` | The sample EditMode test, which covers the validator. |

## Adopt it in your project

1. Copy `.github/` into your repository. Your Unity project must be at the repository root: `Assets/`, `Packages/` and `ProjectSettings/` at the top level.
2. Copy `Assets/Editor/CIHelper.cs` and `Assets/Editor/WebGLBuildOutputValidator.cs` into an Editor folder or an Editor-only assembly of your project. You can use your own build method instead: change `-executeMethod CIHelper.Build` in `build.yaml`. Keep the `[CIHelper] Build failed:` log line, or change the pattern in `annotate_build_failure.sh`.
3. Edit `.github/workflows/build_profiles.json` to list the players you build (see [Build profiles](#build-profiles)).
4. Add the secrets from [Licensing](#licensing).
5. Optional: set the variables in [Variables](#variables).
6. Push to a branch and open a pull request. `Test` and `Build` run on every pull request and on every push to `main`, except for changes that touch only Markdown files or `LICENSE`.

The Unity version comes from `ProjectSettings/ProjectVersion.txt`. To change it, upgrade the project in the Editor and commit the new `ProjectVersion.txt`. No workflow hard-codes a version.

If your default branch is not `main`, change `branches: [main]` in `test.yaml`, `build.yaml` and `check_scripts.yaml`.

### Secrets

| Secret | Needed for |
|---|---|
| `UNITY_SERIAL` | Every Unity job on a runner that has no active license. |
| `UNITY_EMAIL`, `UNITY_PASSWORD` | Editor activation, and the Editor fallback when the license is returned. |
| `UNITY_SERVICE_ACCOUNT_ID`, `UNITY_SERVICE_ACCOUNT_SECRET` | Optional. CLI activation with `unity license activate --serial`. |

When `UNITY_SERIAL` is not set and `UNITY_RUNS_ON` is empty, a `preflight` job in `Test`, `Build` and `Cache warm` skips every Unity job and writes a line to the job summary. The runs stay green. `Check scripts` needs no secrets and always runs. A self-hosted runner with a machine license needs only `UNITY_RUNS_ON`.

### Variables

| Variable | Default | Effect |
|---|---|---|
| `UNITY_RUNS_ON` | `"ubuntu-latest"` | The `runs-on` value of every Unity job, as JSON. For example `["self-hosted", "linux", "unity"]`. When it is set, `Cache warm` does not run. |
| `PAGES_PROFILE` | empty | The name of a WebGL profile to deploy to GitHub Pages after a successful build on the default branch. Empty turns the deploy off. |

### Permissions

All workflows run with `contents: read`. Only the Pages deploy job adds `pages: write` and `id-token: write`. No workflow writes to the repository, comments on pull requests or needs a personal access token.

## Workflows

### Test

`unity test . --mode EditMode --output artifacts/test-results.xml -- -nographics -logFile ...`

The arguments after `--` go to the Editor unchanged. `-nographics` lets the Editor start on a runner with no display. If your tests open an `EditorWindow`, remove `-nographics` and wrap the command in `xvfb-run --auto-servernum`.

After the run, `summarize_test_results.py` reads the NUnit XML. It adds one `::error` annotation for each failing test and writes a table of failures to the job summary. If the Editor never wrote the XML, for example because of a compile error, the summary says so, and the Editor log in the `editmode-results` artifact has the cause.

The step reports the exit code as a verdict:

| `unity test` exit | Verdict |
|---|---|
| 0 | `passed` |
| 8 | `tests-failed` |
| 6 | `no-verdict`. The Editor did not finish, for example a compile error or an unlicensed Editor. |
| other | `unexpected-exit-<code>`. This also fails the job. |

### Build

The `profiles` job reads `build_profiles.json`. A manual run can select some profiles with the `profiles` input. The `build` job runs once per profile:

```sh
unity run . --timeout 6000 -- -nographics -buildTarget <target> [-activeBuildProfile <asset>] \
  -executeMethod CIHelper.Build -buildOutput Builds/<name> -logFile artifacts/build.log
```

The build uses `unity run`, not `unity build`, because `unity run` forwards every Editor argument after `--` as it is. `unity run` itself adds `-batchmode`, `-quit` and `-projectPath`, so do not pass them.

`CIHelper.Build` builds the enabled scenes in Build Settings for the active build target. It never switches the target itself, because a target switch can need a domain reload that a batch-mode `-executeMethod` run cannot survive. Instead the Editor switches at startup from `-buildTarget`. `CIHelper` then fails if `-buildTarget` does not name the active target. That happens when the platform module is missing, or when the target is not a [`BuildTarget`](https://docs.unity3d.com/ScriptReference/BuildTarget.html) name (for example `Linux64` instead of `StandaloneLinux64`).

Every failure inside `CIHelper` logs `[CIHelper] Build failed: <exception>` and exits the Editor with code 1. The Unity CLI 1.0.0-beta.10 reports that as exit code 6, the same code as a compile error. So the workflow does not rely on the exit code alone. `annotate_build_failure.sh` finds the `[CIHelper] Build failed:` line in the Editor log and turns it and the next two lines into an `::error` annotation:

| Result | Verdict |
|---|---|
| exit 0 | `built` |
| non-zero, and the log has `[CIHelper] Build failed:` | `build-failed` |
| exit 6 without that line | `editor-failed`: compile error, license or Editor crash. Read the log artifact. |
| other | `unexpected-exit-<code>` |

A WebGL build must pass the same payload contract twice:

- in the Editor, by `WebGLBuildOutputValidator` after `BuildPipeline.BuildPlayer` succeeds;
- in the workflow, by `validate_webgl_payload.sh` before the upload. The Pages job runs it again on the downloaded artifact before it deploys.

The contract: `index.html` is a non-empty file, `Build/` is a directory, and `Build/` holds non-empty `*.loader.js*`, `*.framework.js*` and `*.wasm*` files. The suffixes can have any case and any `.gz` or `.br` compression suffix. `TemplateData/` is not required, because custom WebGL templates often do not emit it. `test_validate_webgl_payload.sh` and the EditMode test hold both halves to the same cases.

Each profile uploads two artifacts: `build-<name>`, which is the player, and `build-<name>-log`, which is the Editor log. Change `ARTIFACT_PREFIX` at the top of `build.yaml` to rename them.

### Deploy

Deploy is the part that differs most between projects, so the default is only the artifact upload. Add your own deploy job after `build`: it downloads `build-<name>` with `actions/download-artifact`, validates it, and ships it.

`build.yaml` has one ready deploy job, for GitHub Pages. To use it:

1. In **Settings → Pages**, set **Source** to **GitHub Actions**.
2. Set the `PAGES_PROFILE` variable to the name of a WebGL profile, for example `webgl`.

After that, each successful build on the default branch deploys that player. GitHub Pages cannot send a `Content-Encoding` header for pre-compressed files, so the sample project sets **Player Settings → Web → Compression Format** to **Disabled**. For a real game, use Brotli on a host that sets the header, or enable **Decompression Fallback**.

### Cache warm

This workflow opens the project once for each cache lane: `editmode`, and every build profile with the same `-buildTarget` and `-activeBuildProfile` as the build. It then saves `Library`. It runs on manual dispatch and every Monday, and it skips Unity entirely when the cache already has an exact entry for the commit. Use it to fill the caches after a cache key change or after GitHub evicts the caches, without running a full build. It runs only on GitHub-hosted runners, because a self-hosted runner keeps its own `Library`.

### Check scripts

This workflow runs every `.github/scripts/test_*.sh` fixture test, then `shellcheck`, then `actionlint`. Run the same checks locally:

```sh
for test in .github/scripts/test_*.sh; do bash "$test"; done
shellcheck .github/scripts/*.sh
actionlint
```

## Build profiles

`build_profiles.json` is a JSON array. Each entry is one matrix job:

```json
[
  { "name": "webgl", "target": "WebGL", "modules": "webgl" },
  { "name": "linux", "target": "StandaloneLinux64", "modules": "" }
]
```

| Field | Meaning |
|---|---|
| `name` | The job label, the artifact suffix, the output folder `Builds/<name>` and the cache lane. Use a short slug with no spaces. |
| `target` | The `BuildTarget` enum name to pass as `-buildTarget`: `WebGL`, `StandaloneLinux64`, `StandaloneWindows64`, `StandaloneOSX`, `Android`, `iOS`. |
| `modules` | Comma-separated Editor module ids for `unity install --module`, for example `webgl`, `android`, `windows-mono`, `mac-mono`, `linux-il2cpp`. To list them, run `unity install <version> --list-modules`. The base Linux Editor already builds `StandaloneLinux64` with Mono. |
| `buildProfile` | Optional. The path to a Unity 6 Build Profile asset, passed as `-activeBuildProfile`. Leave it out to build from the classic Build Settings. |

`CIHelper` names the player file for `StandaloneLinux64` (`<product>.x86_64`), `StandaloneWindows64` (`.exe`), `StandaloneOSX` (`.app`) and `Android` (`.apk`). For all other targets it builds into the folder. Android and iOS need signing material and SDK setup that this repository does not provide.

## Licensing

`setup-unity` runs `.github/scripts/unity_license.sh activate` before any Unity work:

1. If `unity license status` already reports an active license, the script uses that license and stops. The mode is `preexisting`. This is the normal case on a self-hosted runner with a persistent machine license. The script checks the status without the service account variables, so a signed-in service account alone does not count as a license.
2. If `UNITY_SERIAL` is empty, the job fails.
3. If `UNITY_SERVICE_ACCOUNT_ID` and `UNITY_SERVICE_ACCOUNT_SECRET` are set, it runs `unity license activate --serial`. The mode is `cli-serial`. This is the route that `unity ci init` generates. The CLI signs in from those two environment variables.
4. If `UNITY_EMAIL` and `UNITY_PASSWORD` are set, it runs the Editor: `Unity -batchmode -nographics -quit -serial … -username … -password …`. The mode is `editor-serial`. This is the invocation that GameCI uses.
5. After each attempt, the script checks `unity license status` again, because an exit code of 0 does not prove an active license. If no attempt gives an active license, the job fails before any Unity work.

The mode is in the job summary of every run.

`teardown-unity` runs `unity_license.sh return` with `if: always()`. It returns the license with `unity license return --yes`, or with the Editor's `-returnlicense` if that fails. It does this only when this job activated the license. A `preexisting` license is never returned, so a self-hosted runner keeps its machine license. If the return fails, the job gets a warning, not a failure.

### Which serial

- **Unity Pro, Plus or an Enterprise seat:** use your license serial.
- **Unity Personal:** Personal has no serial on the website, but the activation file on a machine where you signed in to the Hub has one. The file is `~/.local/share/unity3d/Unity/Unity_lic.ulf` on Linux, `/Library/Application Support/Unity/Unity_lic.ulf` on macOS and `C:\ProgramData\Unity\Unity_lic.ulf` on Windows. GameCI takes the serial from that file in the same way:

  ```sh
  sed -n 's/.*<DeveloperData Value="\([^"]*\)".*/\1/p' Unity_lic.ulf | base64 -d | tail -c +5
  ```

  Store the output as `UNITY_SERIAL`, and do not commit the `.ulf` file. Check that CI use is within your Unity license terms.

### Failure modes

- **A stored `.ulf` fails on a new runner.** An activation file (`unity license activate --file`, or `-manualLicenseFile`) is bound to the machine that made it. On a new runner it fails with `Code 400 ... TimeStamp validation failed`. Unity also dropped manual activation for Personal licenses. This is why the example does not use a `UNITY_LICENSE` file secret.
- **`This license requires a signed-in Unity account`.** `unity license activate --serial` without a signed-in account gives this error. Set the service account secrets, or let the Editor route sign in with the email and password.
- **Two-factor authentication.** GameCI users report that an account with two-factor authentication cannot sign in with `-username` and `-password`. Use a dedicated CI account.
- **Activation limit.** Each fresh GitHub-hosted runner is a new machine. A license that is not returned stays registered to a machine that no longer exists. The teardown returns the license, but look at the teardown warning if the account reaches its activation limit.
- **Credentials in the process list.** The Editor takes the password on its command line. GitHub masks secrets in the log. On a shared self-hosted host, other local users can read the password with `ps`. Use a dedicated account, or a runner that already has a license.

### What is proven and what is not

Proven on a local Linux machine with Unity CLI 1.0.0-beta.10 and Editor 6000.3.16f1, with a license that was already active:

- the `preexisting` early return;
- `unity test` with `-- -nographics -logFile` and no display. It gives exit code 0 when all tests pass and 8 when a test fails;
- `unity run` WebGL and `StandaloneLinux64` builds through `CIHelper.Build`. The WebGL output passes `validate_webgl_payload.sh`;
- a `CIHelper` failure gives CLI exit code 6, and `annotate_build_failure.sh` finds the failure in the real Editor log;
- the `-buildTarget` guard rejects `Linux64`.

The fixture tests also cover each branch of `unity_license.sh` against stub `unity` and Editor binaries.

Not proven, because this repository has not run on GitHub yet:

- `cli-serial` and `editor-serial` activation on a fresh runner, and the license return at teardown. The same Editor `-serial -username -password` invocation licenses GameCI runs, but it has not run here;
- whether `unity license return` works after an Editor activation without a signed-in CLI;
- the Editor and WebGL module install on `ubuntu-latest`, and whether `unity_repair_modules.sh` still has anything to repair on CLI 1.0.0-beta.10;
- the disk cleanup thresholds, the Library, LFS and Pages steps, and all timings.

The first run on GitHub will settle these points.

## Caches

### Library

`library-cache` uses one key scheme for every lane:

```text
Library-v1-<os>-<lane>-<hash of ProjectVersion.txt>-<hash of packages-lock.json>-<commit sha>
```

Restore falls back first to the newest entry with the same packages, then to the newest entry for the same Editor version. It never falls back to a `Library` from a different Editor version or a different lane. A lane is the test job (`editmode`) or a build profile name, because a `Library` holds imports for one build target and one set of scripting defines.

The key scheme follows these rules:

- **Only open the project under the conditions of the job that restores the Library.** A `Library` imported under different conditions is worse than no `Library`, because its failures are silent. One example: an import against Git LFS pointer files packs sprite atlases from those pointers and ships an oversized player. So every Unity job restores LFS objects before Unity starts, and `Cache warm` passes the same `-buildTarget` and `-activeBuildProfile` as the build.
- **Save only outside pull requests.** A pull request can restore entries from the default branch, but other pull requests cannot read entries that a pull request saves. Those entries only use up the repository's 10 GB cache budget and push out the entries that everyone can use. So pull requests restore, and pushes, manual runs and `Cache warm` save.
- **Change `v1` in the key to retire a bad generation.** If a bad `Library` gets into the cache, change `v1` to `v2` in `library-cache/action.yaml`. The fallbacks stop at that prefix, so no job restores the old entries again.

On a self-hosted runner, `library-cache` does nothing. The checkout keeps `Library` in the runner's work folder (`clean: false`), and `git clean -ffdx -e Library` removes everything else that the last job left.

### Git LFS

`restore-git-lfs` does nothing when `.gitattributes` has no `filter=lfs` rule. Otherwise it computes a key from `git lfs ls-files --long`, restores `.git/lfs` on GitHub-hosted runners, runs `git lfs pull`, and saves the cache outside pull requests.

### The Editor is not cached

The base Linux Editor is about 8 GB on disk, and the WebGL module adds about 5.4 GB. One WebGL Editor entry is larger than the whole 10 GB Actions cache budget, and it would push out every `Library` entry. So each GitHub-hosted job installs the Editor from Unity's CDN. On a self-hosted runner, install the Editor once, and `setup-unity` skips the install when `unity editors --installed` already lists the version. That runner must already have the modules that your profiles need.

## GitHub-hosted and self-hosted runners

| | GitHub-hosted (default) | Self-hosted (`UNITY_RUNS_ON`) |
|---|---|---|
| License | Activated with the secrets for each job, and returned at teardown. | Can keep a persistent machine license. The job uses it (`preexisting`) and never returns it. |
| Editor | Installed for each job. Expect several minutes, and more with the WebGL module. | Installed once. The action skips the install if the version is present. |
| `Library` | Actions cache. | Kept in the work folder. |
| Disk | `free-disk-space` removes Android, .NET, GHC, CodeQL, Swift and Docker images when the job needs more space. | Checked only. The job fails early instead of deleting anything. |
| Needs | Nothing. | `bash`, `curl`, `jq`, `git`, `git-lfs`, `python3`, `timeout`, and the Editor's runtime libraries. |

On a fresh hosted image, if the Editor exits at once because a shared library is missing, install the package list that `unity ci init --dry-run` prints.

Run only one Unity job at a time on each self-hosted runner. Parallel jobs on one host share `~/.config/unity3d` and the machine license.

## Other things to know

- **The CLI version is pinned.** `setup-unity` installs `1.0.0-beta.10` and fails if the installer delivers a different version. Unity publishes only beta releases of the CLI, and a pin keeps a new beta out of your checks until a commit changes it. Change `cli-version` in `setup-unity`, or pass it as an input.
- **Module unpack defect.** Unity CLI 1.0.0-beta.6 unpacked platform modules one folder too deep (`PlaybackEngines/<Module>/Editor/Data/PlaybackEngines/<Module>/`). The install still reported success, and the build failed much later. `unity_repair_modules.sh` fixes that layout, and does nothing when the layout is correct.
- **Audio needs ffmpeg.** The Unity audio importer calls `ffmpeg` to make AAC, which WebGL requires, and `ubuntu-latest` does not have ffmpeg. If your project imports audio for WebGL, add `sudo apt-get install -y ffmpeg` before the build step.
- **Headless Editor runs change tracked files.** Opening a project in batch mode can rewrite files in `ProjectSettings/`. That does not matter in CI. On your own machine, check `git status` after you run these commands.

## Run it locally

With the Unity CLI and the Editor from `ProjectVersion.txt` installed:

```sh
unity test . --mode EditMode --output artifacts/test-results.xml -- -nographics -logFile "$PWD/artifacts/editmode.log"
python3 .github/scripts/summarize_test_results.py artifacts/test-results.xml

unity run . -- -nographics -buildTarget WebGL -executeMethod CIHelper.Build -buildOutput Builds/webgl -logFile "$PWD/artifacts/build.log"
bash .github/scripts/validate_webgl_payload.sh Builds/webgl
```

## License

MIT. See [LICENSE](LICENSE).
