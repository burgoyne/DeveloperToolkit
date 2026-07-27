# AppendConfluencePage.ps1

Adds content from a local file to an existing Confluence Cloud page.

The script reads Confluence `storage` representation markup from a local UTF-8 file, combines it with the current page body, and publishes a new version of the page. By default, the new content is prepended above the existing page body.

## Requirements

- PowerShell 7.6 or later.
- A Confluence Cloud site.
- An Atlassian account that can view and update the target page.
- An Atlassian API token for that account.
- A local content file containing Confluence-compatible storage markup.

## Authentication

Set these environment variables before running the script:

| Variable | Description | Example |
| --- | --- | --- |
| `CONFLUENCE_USERNAME` | Atlassian account email address. | `user@example.com` |
| `CONFLUENCE_API_TOKEN` | Atlassian API token for the account. | `ATATT...` |

PowerShell example:

```powershell
$env:CONFLUENCE_USERNAME = "user@example.com"
$env:CONFLUENCE_API_TOKEN = "<api-token>"
```

## Parameters

| Parameter | Required | Description |
| --- | --- | --- |
| `BaseUrl` | Yes | Base URL for the Confluence Cloud site. Must use HTTPS and include `/wiki`. |
| `PageId` | Yes | Numeric ID of the Confluence page to update. |
| `FilePath` | Yes | Path to the local content file containing Confluence `storage` representation markup. |
| `Placement` | No | Where to place the new content relative to the existing page body. Valid values are `Prepend` and `Append`. The default is `Prepend`. |
| `Separator` | No | Confluence storage markup inserted between the new and existing content. The default is `<hr />`. Pass an empty string to use no separator. |
| `VersionMessage` | No | Message associated with the new Confluence page version. When omitted, the script generates one from the source filename. |
| `MinorEdit` | No | Marks the new Confluence version as a minor edit. |
| `ShowCombinedBodyPreview` | No | Writes a preview of the combined page body before updating Confluence. |
| `PreviewLength` | No | Maximum number of characters displayed by `ShowCombinedBodyPreview`. The default is `2000`. |

## Usage

Prepend content above the existing page body:

```powershell
.\AppendConfluencePage.ps1 `
    -BaseUrl "https://your-domain.atlassian.net/wiki" `
    -PageId "1688240435" `
    -FilePath ".\release-notes.html"
```

Append content below the existing page body:

```powershell
.\AppendConfluencePage.ps1 `
    -BaseUrl "https://your-domain.atlassian.net/wiki" `
    -PageId "1688240435" `
    -FilePath ".\release-notes.html" `
    -Placement Append
```

Preview the combined body and use `-WhatIf` to avoid updating Confluence:

```powershell
.\AppendConfluencePage.ps1 `
    -BaseUrl "https://your-domain.atlassian.net/wiki" `
    -PageId "1688240435" `
    -FilePath ".\release-notes.html" `
    -ShowCombinedBodyPreview `
    -WhatIf
```

Use a custom version message and mark the update as a minor edit:

```powershell
.\AppendConfluencePage.ps1 `
    -BaseUrl "https://your-domain.atlassian.net/wiki" `
    -PageId "1688240435" `
    -FilePath ".\release-notes.html" `
    -VersionMessage "Added release notes for version 2.4.0" `
    -MinorEdit
```

## Behavior

The script performs these steps:

1. Validates `BaseUrl` as an HTTPS Confluence Cloud `/wiki` URL.
2. Reads and validates `CONFLUENCE_USERNAME` and `CONFLUENCE_API_TOKEN`.
3. Confirms the local content file exists and is not empty.
4. Fetches the current Confluence page body in `storage` format, including version metadata.
5. Confirms the returned page ID, status, title, version, and body are usable.
6. Combines the new content with the existing body according to `Placement` and `Separator`.
7. Generates the next page version number.
8. Shows a combined body preview when `ShowCombinedBodyPreview` is supplied.
9. Updates the page unless `-WhatIf` prevents the operation.
10. Returns structured output with the update details.

## Output

On a real update, the script writes a `Confluence.PageContentUpdateResult` object:

| Property | Description |
| --- | --- |
| `Updated` | `true` when the page was updated. |
| `PageId` | ID of the updated Confluence page. |
| `Title` | Title returned by Confluence for the updated page. |
| `PreviousVersion` | Page version before the update. |
| `Version` | Page version created by the update. |
| `Placement` | Placement used to combine the new and existing content. |
| `SourceFile` | Resolved local file path that supplied the new content. |
| `AddedCharacters` | Character count of the added content. |
| `CombinedLength` | Character count of the full combined page body. |
| `PageUrl` | Browser URL for the updated page. |

When `-WhatIf` prevents the update, the script returns the same result type with `Updated` set to `false` and `ProposedVersion` set to the version number that would have been created.

## Content File Notes

`FilePath` is read as UTF-8 text and sent as part of the `body.value` for Confluence's `storage` representation.

The file should contain markup that Confluence accepts in storage format, such as paragraphs, tables, headings, links, and supported Confluence storage elements. Avoid wrapping the content in a complete standalone HTML document unless Confluence accepts that markup for your target page body. Utilizing AI to format your document into a Confluence-accepted style (with panels, etc.) is a great way to get a well designed file that doesn't require modifications in Confluence. 

## Failure Cases

The script stops before updating a page when:

- A required environment variable is missing or blank.
- `BaseUrl` is not a valid HTTPS Confluence Cloud `/wiki` URL.
- The local content file does not exist.
- The local content file is empty.
- The page cannot be found or is not accessible.
- Confluence returns a page ID that does not match `PageId`.
- The page is not in `current` status.
- Confluence does not return the page title, version, or storage body.

Confluence API failures include the request method, URL, HTTP status when available, exception message, and response body when available.
