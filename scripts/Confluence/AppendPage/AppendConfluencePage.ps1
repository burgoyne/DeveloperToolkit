#Requires -Version 7.6

[CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = "Medium"
)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+$')]
    [string]$PageId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath,

    [Parameter()]
    [ValidateSet("Prepend", "Append")]
    [string]$Placement = "Prepend",

    [Parameter()]
    [AllowEmptyString()]
    [string]$Separator = "<hr />",

    [Parameter()]
    [AllowEmptyString()]
    [string]$VersionMessage,

    [Parameter()]
    [switch]$MinorEdit,

    [Parameter()]
    [switch]$ShowCombinedBodyPreview,

    [Parameter()]
    [ValidateRange(1, 100000)]
    [int]$PreviewLength = 2000
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
        throw "BaseUrl is not a valid absolute URL: $BaseUrl"
    }

    if ($parsedUri.Scheme -ne [Uri]::UriSchemeHttps) {
        throw "BaseUrl must use HTTPS."
    }

    if (
        -not [string]::IsNullOrWhiteSpace($parsedUri.Query) -or
        -not [string]::IsNullOrWhiteSpace($parsedUri.Fragment)
    ) {
        throw "BaseUrl must not contain a query string or fragment."
    }

    $normalizedUrl = $parsedUri.AbsoluteUri.TrimEnd('/')

    if (
        -not $normalizedUrl.EndsWith(
            "/wiki",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw @"
BaseUrl must include the Confluence Cloud '/wiki' path.

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
        [ValidateSet("Get", "Put")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers,

        [Parameter()]
        [object]$Body
    )

    $invokeParameters = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ErrorAction = "Stop"
    }

    if ($PSBoundParameters.ContainsKey("Body")) {
        $jsonBody = $Body |
            ConvertTo-Json -Depth 20 -Compress

        $invokeParameters.Body = [Text.Encoding]::UTF8.GetBytes($jsonBody)
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

function Get-ConfluencePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$PageId,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $requestUrl = (
        "{0}/api/v2/pages/{1}?body-format=storage&include-version=true" -f
        $BaseUrl,
        $PageId
    )

    Write-Verbose "Fetching Confluence page '$PageId'."

    return Invoke-ConfluenceApi `
        -Method Get `
        -Uri $requestUrl `
        -Headers $Headers
}

function Update-ConfluencePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$PageId,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [int]$VersionNumber,

        [Parameter(Mandatory = $true)]
        [string]$StorageBody,

        [Parameter(Mandatory = $true)]
        [string]$VersionMessage,

        [Parameter(Mandatory = $true)]
        [bool]$MinorEdit,

        [Parameter(Mandatory = $true)]
        [Collections.IDictionary]$Headers
    )

    $requestUrl = "{0}/api/v2/pages/{1}" -f $BaseUrl, $PageId

    $payload = @{
        id     = $PageId
        status = "current"
        title  = $Title
        body   = @{
            representation = "storage"
            value          = $StorageBody
        }
        version = @{
            number    = $VersionNumber
            message   = $VersionMessage
            minorEdit = $MinorEdit
        }
    }

    Write-Verbose (
        "Updating Confluence page '{0}' to version {1}." -f
        $PageId,
        $VersionNumber
    )

    return Invoke-ConfluenceApi `
        -Method Put `
        -Uri $requestUrl `
        -Headers $Headers `
        -Body $payload
}

function Join-ConfluenceStorageBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NewContent,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExistingContent,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Prepend", "Append")]
        [string]$Placement,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Separator
    )

    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        return $NewContent
    }

    $contentParts = switch ($Placement) {
        "Prepend" {
            @(
                $NewContent
                $Separator
                $ExistingContent
            )
        }

        "Append" {
            @(
                $ExistingContent
                $Separator
                $NewContent
            )
        }
    }

    return (
        $contentParts |
            Where-Object {
                -not [string]::IsNullOrEmpty([string]$_)
            }
    ) -join [Environment]::NewLine
}

$normalizedBaseUrl = Get-NormalizedConfluenceBaseUrl `
    -BaseUrl $BaseUrl

$username = Get-RequiredEnvironmentVariable `
    -Name "CONFLUENCE_USERNAME"

$apiToken = Get-RequiredEnvironmentVariable `
    -Name "CONFLUENCE_API_TOKEN"

$headers = New-ConfluenceHeaders `
    -Username $username `
    -ApiToken $apiToken

if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "Content file was not found: $FilePath"
}

$resolvedFilePath = (
    Resolve-Path -LiteralPath $FilePath
).ProviderPath

$newContent = Get-Content `
    -LiteralPath $resolvedFilePath `
    -Raw `
    -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($newContent)) {
    throw "Content file is empty: $resolvedFilePath"
}

Write-Verbose (
    "Loaded '{0}' ({1} characters)." -f
    $resolvedFilePath,
    $newContent.Length
)

$page = Get-ConfluencePage `
    -BaseUrl $normalizedBaseUrl `
    -PageId $PageId `
    -Headers $headers

if ($null -eq $page) {
    throw "Confluence returned no data for page '$PageId'."
}

if ([string]$page.id -ne $PageId) {
    throw @"
The returned Confluence page ID did not match the requested page ID.

Requested page ID: $PageId
Returned page ID: $($page.id)
"@
}

if ([string]$page.status -ne "current") {
    throw @"
Page '$PageId' does not have a current published status.

Page status: $($page.status)
"@
}

if ([string]::IsNullOrWhiteSpace([string]$page.title)) {
    throw "Confluence did not return a title for page '$PageId'."
}

if (
    $null -eq $page.version -or
    $null -eq $page.version.number
) {
    throw "Confluence did not return version information for page '$PageId'."
}

if (
    $null -eq $page.body -or
    $null -eq $page.body.storage
) {
    throw @"
Confluence did not return the page body in storage format.

Page ID: $PageId
"@
}

$currentTitle = [string]$page.title
$currentVersion = [int]$page.version.number

$storageValueProperty = $page.body.storage.PSObject.Properties["value"]

$currentBody = if ($null -eq $storageValueProperty) {
    ""
}
else {
    [string]$storageValueProperty.Value
}

Write-Verbose "Page title: $currentTitle"
Write-Verbose "Current version: $currentVersion"
Write-Verbose "Existing body length: $($currentBody.Length) characters."

$combinedBody = Join-ConfluenceStorageBody `
    -NewContent $newContent `
    -ExistingContent $currentBody `
    -Placement $Placement `
    -Separator $Separator

$nextVersion = $currentVersion + 1

if ([string]::IsNullOrWhiteSpace($VersionMessage)) {
    $sourceFileName = [IO.Path]::GetFileName($resolvedFilePath)
    $VersionMessage = "Added content from '$sourceFileName'."
}

Write-Verbose "Placement: $Placement"
Write-Verbose "Combined body length: $($combinedBody.Length) characters."
Write-Verbose "Proposed version: $nextVersion"

if ($ShowCombinedBodyPreview) {
    $previewCharacterCount = [Math]::Min(
        $PreviewLength,
        $combinedBody.Length
    )

    $preview = $combinedBody.Substring(
        0,
        $previewCharacterCount
    )

    Write-Host ""
    Write-Host "----- Combined Body Preview -----" -ForegroundColor Yellow
    Write-Host $preview

    if ($combinedBody.Length -gt $PreviewLength) {
        Write-Host ""
        Write-Host (
            "Preview truncated after {0} characters." -f
            $PreviewLength
        ) -ForegroundColor DarkYellow
    }

    Write-Host "---------------------------------" -ForegroundColor Yellow
}

$targetDescription = (
    "Confluence page '{0}' ({1})" -f
    $currentTitle,
    $PageId
)

$operationDescription = (
    "{0} content from '{1}' and create version {2}" -f
    $Placement,
    $resolvedFilePath,
    $nextVersion
)

if (
    -not $PSCmdlet.ShouldProcess(
        $targetDescription,
        $operationDescription
    )
) {
    return [PSCustomObject]@{
        PSTypeName       = "Confluence.PageContentUpdateResult"
        Updated          = $false
        PageId           = $PageId
        Title            = $currentTitle
        PreviousVersion  = $currentVersion
        ProposedVersion  = $nextVersion
        Placement        = $Placement
        SourceFile       = $resolvedFilePath
        AddedCharacters  = $newContent.Length
        CombinedLength   = $combinedBody.Length
    }
}

$response = Update-ConfluencePage `
    -BaseUrl $normalizedBaseUrl `
    -PageId $PageId `
    -Title $currentTitle `
    -VersionNumber $nextVersion `
    -StorageBody $combinedBody `
    -VersionMessage $VersionMessage `
    -MinorEdit ([bool]$MinorEdit) `
    -Headers $headers

if (
    $null -eq $response -or
    [string]::IsNullOrWhiteSpace([string]$response.id)
) {
    throw "Confluence did not return page data after the update."
}

$pageUrl = (
    "{0}/pages/viewpage.action?pageId={1}" -f
    $normalizedBaseUrl,
    $PageId
)

[PSCustomObject]@{
    PSTypeName      = "Confluence.PageContentUpdateResult"
    Updated         = $true
    PageId          = [string]$response.id
    Title           = [string]$response.title
    PreviousVersion = $currentVersion
    Version         = [int]$response.version.number
    Placement       = $Placement
    SourceFile      = $resolvedFilePath
    AddedCharacters = $newContent.Length
    CombinedLength  = $combinedBody.Length
    PageUrl         = $pageUrl
}
