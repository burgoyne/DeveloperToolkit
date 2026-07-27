#Requires -Version 7.6

[CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = "Low"
)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LocalHtmlPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SpaceKey,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+$')]
    [string]$FolderId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RequiredEnvironmentVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is not set."
    }

    return $value.Trim()
}

function Get-NormalizedConfluenceBaseUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl
    )

    $parsedUri = $null

    if (
        -not [Uri]::TryCreate(
            $BaseUrl,
            [UriKind]::Absolute,
            [ref]$parsedUri
        )
    ) {
        throw "CONFLUENCE_BASE_URL is not a valid absolute URL."
    }

    if ($parsedUri.Scheme -ne [Uri]::UriSchemeHttps) {
        throw "CONFLUENCE_BASE_URL must use HTTPS."
    }

    if (
        -not [string]::IsNullOrWhiteSpace($parsedUri.Query) -or
        -not [string]::IsNullOrWhiteSpace($parsedUri.Fragment)
    ) {
        throw "CONFLUENCE_BASE_URL must not contain a query string or fragment."
    }

    $normalizedUrl = $parsedUri.AbsoluteUri.TrimEnd('/')

    if (
        -not $normalizedUrl.EndsWith(
            "/wiki",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw @"
CONFLUENCE_BASE_URL must include the Confluence '/wiki' path.

Example:
https://your-domain.atlassian.net/wiki
"@
    }

    return $normalizedUrl
}

function New-ConfluenceHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiToken
    )

    $credentials = "${Username}:${ApiToken}"
    $credentialBytes = [Text.Encoding]::UTF8.GetBytes($credentials)
    $encodedCredentials = [Convert]::ToBase64String($credentialBytes)

    return @{
        Authorization = "Basic $encodedCredentials"
        Accept        = "application/json"
    }
}

function Get-ConfluenceErrorDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Management.Automation.ErrorRecord]$ErrorRecord
    )

    $statusCode = $null
    $statusDescription = $null
    $responseBody = $null
    $response = $ErrorRecord.Exception.Response

    if ($null -ne $response) {
        try {
            $statusCode = [int]$response.StatusCode
        }
        catch {
        }

        try {
            $statusDescription = [string]$response.ReasonPhrase
        }
        catch {
        }

        try {
            if ($null -ne $response.Content) {
                $responseBody = $response.Content
                    .ReadAsStringAsync()
                    .GetAwaiter()
                    .GetResult()
            }
        }
        catch {
        }
    }

    if (
        [string]::IsNullOrWhiteSpace($responseBody) -and
        $null -ne $ErrorRecord.ErrorDetails
    ) {
        $responseBody = $ErrorRecord.ErrorDetails.Message
    }

    return [PSCustomObject]@{
        StatusCode        = $statusCode
        StatusDescription = $statusDescription
        ResponseBody      = $responseBody
        Message           = $ErrorRecord.Exception.Message
    }
}

function Invoke-ConfluenceApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Get", "Post", "Put", "Delete")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Body
    )

    $invokeParameters = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ErrorAction = "Stop"
    }

    if ($PSBoundParameters.ContainsKey("Body")) {
        $invokeParameters.Body = [Text.Encoding]::UTF8.GetBytes($Body)
        $invokeParameters.ContentType = "application/json; charset=utf-8"
    }

    try {
        return Invoke-RestMethod @invokeParameters
    }
    catch {
        $details = Get-ConfluenceErrorDetails -ErrorRecord $_

        $statusText = if ($details.StatusCode) {
            "HTTP $($details.StatusCode) $($details.StatusDescription)".Trim()
        }
        else {
            "No HTTP status was returned"
        }

        $message = @(
            "Confluence API request failed."
            "Method: $Method"
            "URL: $Uri"
            "Status: $statusText"
            "Message: $($details.Message)"
        )

        if (-not [string]::IsNullOrWhiteSpace($details.ResponseBody)) {
            $message += "Response: $($details.ResponseBody)"
        }

        throw ($message -join [Environment]::NewLine)
    }
}

function Get-ConfluenceSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$SpaceKey,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $encodedSpaceKey = [Uri]::EscapeDataString($SpaceKey)
    $requestUrl = "$BaseUrl/api/v2/spaces?keys=$encodedSpaceKey&limit=2"

    Write-Verbose "Resolving Confluence space '$SpaceKey'."

    $response = Invoke-ConfluenceApi `
        -Method Get `
        -Uri $requestUrl `
        -Headers $Headers

    $matchingSpaces = @(
        $response.results |
            Where-Object {
                [string]::Equals(
                    [string]$_.key,
                    $SpaceKey,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )

    if ($matchingSpaces.Count -eq 0) {
        throw "Confluence space '$SpaceKey' was not found or is not accessible."
    }

    if ($matchingSpaces.Count -gt 1) {
        throw "More than one Confluence space matched key '$SpaceKey'."
    }

    return $matchingSpaces[0]
}

function Get-ConfluenceFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$FolderId,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $requestUrl = "$BaseUrl/api/v2/folders/$FolderId"

    Write-Verbose "Validating Confluence folder '$FolderId'."

    return Invoke-ConfluenceApi `
        -Method Get `
        -Uri $requestUrl `
        -Headers $Headers
}

function New-ConfluencePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$SpaceId,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$StorageBody,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $requestUrl = "$BaseUrl/api/v2/pages"

    $payload = @{
        spaceId = $SpaceId
        status  = "current"
        title   = $Title
        body    = @{
            representation = "storage"
            value          = $StorageBody
        }
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "Creating Confluence page '$Title'."

    return Invoke-ConfluenceApi `
        -Method Post `
        -Uri $requestUrl `
        -Headers $Headers `
        -Body $payload
}

function Move-ConfluencePageToFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$PageId,

        [Parameter(Mandatory = $true)]
        [string]$FolderId,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $requestUrl = (
        "$BaseUrl/rest/api/content/{0}/move/append/{1}" -f
        $PageId,
        $FolderId
    )

    Write-Verbose "Moving page '$PageId' beneath folder '$FolderId'."

    Invoke-ConfluenceApi `
        -Method Put `
        -Uri $requestUrl `
        -Headers $Headers |
        Out-Null
}

$baseUrl = Get-NormalizedConfluenceBaseUrl `
    -BaseUrl (Get-RequiredEnvironmentVariable -Name "CONFLUENCE_BASE_URL")

$username = Get-RequiredEnvironmentVariable `
    -Name "CONFLUENCE_USERNAME"

$apiToken = Get-RequiredEnvironmentVariable `
    -Name "CONFLUENCE_API_TOKEN"

$headers = New-ConfluenceHeaders `
    -Username $username `
    -ApiToken $apiToken

if (-not (Test-Path -LiteralPath $LocalHtmlPath -PathType Leaf)) {
    throw "Content file was not found: $LocalHtmlPath"
}

$resolvedFilePath = (
    Resolve-Path -LiteralPath $LocalHtmlPath
).ProviderPath

$contentBody = Get-Content `
    -LiteralPath $resolvedFilePath `
    -Raw `
    -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($contentBody)) {
    throw "Content file is empty: $resolvedFilePath"
}

Write-Verbose "Loaded '$resolvedFilePath' ($($contentBody.Length) characters)."

$space = Get-ConfluenceSpace `
    -BaseUrl $baseUrl `
    -SpaceKey $SpaceKey `
    -Headers $headers

$folder = Get-ConfluenceFolder `
    -BaseUrl $baseUrl `
    -FolderId $FolderId `
    -Headers $headers

if ([string]$folder.spaceId -ne [string]$space.id) {
    throw @"
Folder '$FolderId' does not belong to space '$SpaceKey'.

Folder space ID: $($folder.spaceId)
Requested space ID: $($space.id)
"@
}

$destinationDescription = (
    "space '{0}', folder '{1}' ({2})" -f
    $SpaceKey,
    $folder.title,
    $FolderId
)

if (
    -not $PSCmdlet.ShouldProcess(
        $destinationDescription,
        "Create Confluence page '$Title'"
    )
) {
    return
}

$createdPage = New-ConfluencePage `
    -BaseUrl $baseUrl `
    -SpaceId ([string]$space.id) `
    -Title $Title `
    -StorageBody $contentBody `
    -Headers $headers

if (
    $null -eq $createdPage -or
    [string]::IsNullOrWhiteSpace([string]$createdPage.id)
) {
    throw "Confluence did not return an ID for the newly created page."
}

$createdPageId = [string]$createdPage.id

try {
    Move-ConfluencePageToFolder `
        -BaseUrl $baseUrl `
        -PageId $createdPageId `
        -FolderId $FolderId `
        -Headers $headers
}
catch {
    throw @"
The Confluence page was created, but it could not be moved beneath the requested folder.

Page title: $Title
Page ID: $createdPageId
Folder ID: $FolderId

The page may need to be moved or deleted manually.

Move error:
$($_.Exception.Message)
"@
}

$pageUrl = "$baseUrl/pages/viewpage.action?pageId=$createdPageId"

[PSCustomObject]@{
    PSTypeName  = "Confluence.PagePublishResult"
    PageId      = $createdPageId
    Title       = [string]$createdPage.title
    Version     = [int]$createdPage.version.number
    SpaceKey    = [string]$space.key
    SpaceId     = [string]$space.id
    FolderId    = [string]$folder.id
    FolderTitle = [string]$folder.title
    PageUrl     = $pageUrl
}
