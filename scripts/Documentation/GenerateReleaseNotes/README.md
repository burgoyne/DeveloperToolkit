# GenerateReleaseNotes.ps1

Generates structured release note data from GitHub commits and merged pull requests between two refs.

The script compares a base ref and head ref with the GitHub API, finds merged pull requests associated with the comparison commits, asks Codex to create stakeholder-friendly summaries, and writes the result to a JSON file in the current working directory.

## Requirements

- PowerShell 7.6 or later.
- GitHub CLI (`gh`) installed and available on `PATH`.
- Codex CLI (`codex`) installed and available on `PATH`.
- GitHub CLI authentication for the target repository.
- Repository access that can read commits and pull request metadata.

## Authentication

Authenticate the GitHub CLI before running the script:

```powershell
gh auth login
```

Alternatively, provide a `GH_TOKEN` that allows `gh api` to read the target repository.

Codex CLI must also be configured so `codex exec` can run non-interactively.

## Parameters

| Parameter | Required | Description |
| --- | --- | --- |
| `Repository` | Yes | GitHub repository in `owner/name` format. |
| `BaseRef` | Yes | Base ref for the comparison. This can be a branch, tag, or SHA accepted by GitHub compare APIs. |
| `HeadRef` | Yes | Head ref for the comparison. This can be a branch, tag, or SHA accepted by GitHub compare APIs. |
| `JsonFileName` | No | Output JSON file name. The default is `release-notes.json`. This must be a file name only and must use the `.json` extension. |

## Usage

Generate release note data between two tags:

```powershell
.\GenerateReleaseNotes.ps1 `
    -Repository "octo-org/example-service" `
    -BaseRef "v2.3.0" `
    -HeadRef "v2.4.0"
```

Write to a custom JSON file name:

```powershell
.\GenerateReleaseNotes.ps1 `
    -Repository "octo-org/example-service" `
    -BaseRef "v2.3.0" `
    -HeadRef "v2.4.0" `
    -JsonFileName "v2.4.0-release-notes.json"
```

Compare a release branch to `main`:

```powershell
.\GenerateReleaseNotes.ps1 `
    -Repository "octo-org/example-service" `
    -BaseRef "release/2.3" `
    -HeadRef "main"
```

## Behavior

The script performs these steps:

1. Validates the output file name.
2. Confirms `gh` and `codex` are available on `PATH`.
3. Confirms the GitHub CLI is authenticated.
4. Calls the GitHub compare API for `BaseRef...HeadRef`.
5. Collects unique comparison commits.
6. Looks up pull requests associated with each commit.
7. Keeps only merged pull requests.
8. Sends pull request titles, descriptions, authors, labels, and merge dates to Codex for summarization.
9. Validates that Codex returns one summary for each collected pull request.
10. Writes the generated release data as JSON in the current working directory.

If no merged pull requests are found between the supplied refs, the script still writes JSON with the comparison and commit data. The summary states that no merged pull requests were found.

## Output

The script writes a JSON file named by `JsonFileName` in the current working directory.

Top-level JSON fields:

| Field | Description |
| --- | --- |
| `generatedAt` | UTC timestamp when the file was generated. |
| `repository` | Repository passed to the script. |
| `comparison` | GitHub comparison metadata, including refs, status, ahead/behind counts, total commits, base SHA, head SHA, and merge base SHA. |
| `summary` | Codex-generated release summary, or a no-pull-requests message. |
| `pullRequests` | Merged pull requests associated with the comparison commits, including generated summaries. |
| `commits` | Unique commits returned by the comparison. |

Each pull request entry includes:

| Field | Description |
| --- | --- |
| `number` | Pull request number. |
| `title` | Pull request title. |
| `description` | Pull request body from GitHub. |
| `author` | GitHub login of the pull request author. |
| `mergedAt` | Merge timestamp. |
| `url` | Browser URL for the pull request. |
| `baseRef` | Pull request base branch. |
| `headRef` | Pull request head branch. |
| `labels` | Pull request labels. |
| `associatedCommitShas` | Comparison commits associated with the pull request. |
| `summary` | Codex-generated summary for the pull request. |

## Codex Summarization

Pull request descriptions are truncated before being sent to Codex when they exceed the script's maximum prompt length per description.

The prompt instructs Codex to treat pull request fields as untrusted source material, ignore boilerplate, avoid invented context, and return JSON that matches the expected output schema. The script rejects Codex output when it is missing the release summary, contains duplicate pull request summaries, includes unexpected pull request numbers, or omits a required pull request summary.

## Failure Cases

The script exits with code `1` when:

- `JsonFileName` includes a path or does not use the `.json` extension.
- `gh` is not available on `PATH`.
- `codex` is not available on `PATH`.
- GitHub CLI authentication is missing or invalid.
- GitHub returns no comparison data.
- A native command exits with a non-zero code.
- Codex does not produce valid structured output.
- The output JSON cannot be written.

On success, the script exits with code `0` and prints the generated JSON path.
