# NewConfluencePage.ps1

Creates a new Confluence Cloud page from a local content file, then moves that page beneath an existing Confluence folder.

The script uses Confluence Cloud REST APIs and publishes the file body as Confluence `storage` representation markup. It creates a new page every time it runs; it does not update or overwrite an existing page with the same title.

## Requirements

- PowerShell 7.6 or later.
- A Confluence Cloud site.
- An Atlassian account that can create pages in the target space and move pages into the target folder.
- An Atlassian API token for that account.
- A local content file containing Confluence-compatible storage markup.

## Authentication

Set these environment variables before running the script:

| Variable | Description | Example |
| --- | --- | --- |
| `CONFLUENCE_BASE_URL` | Base URL for the Confluence Cloud site. Must use HTTPS and include `/wiki`. | `https://your-domain.atlassian.net/wiki` |
| `CONFLUENCE_USERNAME` | Atlassian account email address. | `user@example.com` |
| `CONFLUENCE_API_TOKEN` | Atlassian API token for the account. | `ATATT...` |

PowerShell example:

```powershell
$env:CONFLUENCE_BASE_URL = "https://your-domain.atlassian.net/wiki"
$env:CONFLUENCE_USERNAME = "user@example.com"
$env:CONFLUENCE_API_TOKEN = "<api-token>"
```

## Parameters

| Parameter | Required | Description |
| --- | --- | --- |
| `Title` | Yes | Title of the Confluence page to create. |
| `LocalHtmlPath` | Yes | Path to the local content file. Despite the parameter name, the file should contain Confluence `storage` representation markup, not a full standalone HTML document. |
| `SpaceKey` | Yes | Key of the destination Confluence space. |
| `FolderId` | Yes | Numeric ID of the destination Confluence folder. |

## Usage

Run the script from PowerShell:

```powershell
.\NewConfluencePage.ps1 `
    -Title "Release Notes - 2026-07-27" `
    -LocalHtmlPath ".\release-notes.html" `
    -SpaceKey "WDT" `
    -FolderId "980582536"
```

Use `-Verbose` to show progress while the script resolves the space, validates the folder, creates the page, and moves it:

```powershell
.\NewConfluencePage.ps1 `
    -Title "Release Notes - 2026-07-27" `
    -LocalHtmlPath ".\release-notes.html" `
    -SpaceKey "WDT" `
    -FolderId "980582536" `
    -Verbose
```

Use `-WhatIf` to validate local inputs and the Confluence destination, then preview the create operation without creating the page:

```powershell
.\NewConfluencePage.ps1 `
    -Title "Release Notes - 2026-07-27" `
    -LocalHtmlPath ".\release-notes.html" `
    -SpaceKey "WDT" `
    -FolderId "980582536" `
    -WhatIf
```

## Behavior

The script performs these steps:

1. Reads and validates `CONFLUENCE_BASE_URL`, `CONFLUENCE_USERNAME`, and `CONFLUENCE_API_TOKEN`.
2. Validates that `CONFLUENCE_BASE_URL` is an HTTPS URL ending with `/wiki`.
3. Confirms the local content file exists and is not empty.
4. Resolves the supplied `SpaceKey` to a Confluence space ID.
5. Loads the folder identified by `FolderId`.
6. Confirms the folder belongs to the requested space.
7. Creates a new current page in the requested space.
8. Moves the created page beneath the requested folder.
9. Returns structured output with the created page details.

If page creation succeeds but moving the page fails, the script stops with an error that includes the created page ID so the page can be moved or deleted manually.

## Output

On success, the script writes a `Confluence.PagePublishResult` object:

| Property | Description |
| --- | --- |
| `PageId` | ID of the created Confluence page. |
| `Title` | Title returned by Confluence for the created page. |
| `Version` | Created page version number. |
| `SpaceKey` | Key of the destination space. |
| `SpaceId` | ID of the destination space. |
| `FolderId` | ID of the destination folder. |
| `FolderTitle` | Title of the destination folder. |
| `PageUrl` | Browser URL for the created page. |

Example:

```text
PageId      : 123456789
Title       : Release Notes - 2026-07-27
Version     : 1
SpaceKey    : WDT
SpaceId     : 987654321
FolderId    : 980582536
FolderTitle : Releases
PageUrl     : https://your-domain.atlassian.net/wiki/pages/viewpage.action?pageId=123456789
```

## Content File Notes

`LocalHtmlPath` is read as UTF-8 text and sent as the `body.value` for Confluence's `storage` representation.

The file should contain markup that Confluence accepts in storage format, such as paragraphs, tables, headings, links, and supported Confluence storage elements. Avoid wrapping the content in a complete standalone HTML document unless Confluence accepts that markup for your target page body. Utilizing AI to format your document into a Confluence-accepted style (with panels, etc.) is a great way to get a well designed file that doesn't require modifications in Confluence.

## Failure Cases

The script stops before creating a page when:

- A required environment variable is missing or blank.
- `CONFLUENCE_BASE_URL` is not a valid HTTPS Confluence Cloud `/wiki` URL.
- The local content file does not exist.
- The local content file is empty.
- The space cannot be found or is not accessible.
- The folder cannot be found or is not accessible.
- The folder belongs to a different space than `SpaceKey`.

Confluence API failures include the request method, URL, HTTP status when available, exception message, and response body when available.
