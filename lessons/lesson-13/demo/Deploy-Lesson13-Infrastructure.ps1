#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions the Azure infrastructure for AI-901 Lesson 13 --
    Build a Text Analysis Application with Foundry (Azure AI Language).

.DESCRIPTION
    Lesson 13 is a code-and-web-app lesson: a Flask front-end
    (demo/webapp/) plus two Python SDK scripts both call Azure AI Language
    with KEYLESS auth. This script stands up the one resource they need.

    NEW FOUNDRY, KEYLESS LANGUAGE. Provisions a multi-service Foundry
    resource (kind=AIServices, S0) that exposes the Language data-plane
    (entities, key phrases, sentiment + opinion mining, summarization).
    A dedicated kind=TextAnalytics Language resource also works -- switch
    -Kind if you prefer a single-service resource.

    Resources provisioned in rg-ai901-lesson13-demo (westus2 by default):

      * ai901-lesson13-language  -- AIServices resource (S0) with a CUSTOM
                                    SUBDOMAIN. The custom subdomain is
                                    MANDATORY: Microsoft Entra (keyless)
                                    auth does not work against a regional
                                    endpoint, only a custom-subdomain one.

      * RBAC: assigns "Cognitive Services User" to the signed-in identity on
        the resource. That is the data-plane role TextAnalyticsClient needs
        when it authenticates with DefaultAzureCredential. Owner on the
        subscription does NOT implicitly grant data-plane access -- the
        keyless gotcha learners hit in production.

    Auth pattern: KEYLESS. Only the endpoint goes in .env; there is no key to
    store. The smoke test uses the management-issued Entra token, not a
    key, to prove the keyless path end to end.

    Cost: < $0.25 per session. Language S0 bills per 1,000 text
    records; a few demo calls are pennies.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson13-demo.

.PARAMETER Location
    Azure region. Default: westus2. Restricted to regions where abstractive
    summarization is GA (swedencentral is excluded -- its summarization is
    preview-only). Verified 2026-06-10 against MS Learn Language region support.

.PARAMETER LanguageName
    Azure resource name for the Language (AIServices) account. Also used as
    the custom subdomain. Default: ai901-lesson13-language.
    NOTE: this must be globally unique -- append a short suffix if needed,
    e.g. ai901-lesson13-language-abc123.

.PARAMETER Kind
    Cognitive Services kind. Default: AIServices (multi-service, Foundry).
    Use TextAnalytics for a dedicated single-service Language resource.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.EXAMPLE
    .\Deploy-Lesson13-Infrastructure.ps1
    Provisions everything, assigns RBAC, runs a keyless smoke test.

.EXAMPLE
    .\Deploy-Lesson13-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Verified:      2026-06-09 against MS Learn "Role-based access control",
                   "TextAnalyticsClient" (Entra/keyless constructor + custom
                   subdomain requirement), and the sentiment-opinion-mining
                   overview (feature retires 2029-03-31 -- still GA today).
    GUI fallback:  Every resource is reproducible in the Azure portal
                   (resource group -> + Create -> Azure AI services), then
                   Access control (IAM) -> Add role assignment -> Cognitive
                   Services User. See lesson-13-demo-runbook.md.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson13-demo',

    [Parameter()]
    # Abstractive summarization (begin_abstract_summary) is region-limited -- these
    # are all in the summarization GA list (verified 2026-06-10 against MS Learn
    # "Azure Language region support"). NOTE: swedencentral is deliberately EXCLUDED
    # here -- its summarization is preview-only, not GA, so it is unsafe for the demo.
    [ValidateSet('westus2', 'eastus2', 'northcentralus', 'westus', 'japaneast',
                 'westeurope', 'northeurope', 'francecentral')]
    [string]$Location = 'westus2',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    # Must be globally unique -- append a short suffix if the default name is already taken.
    [string]$LanguageName = 'ai901-lesson13-language',

    [Parameter()]
    [ValidateSet('AIServices', 'TextAnalytics')]
    [string]$Kind = 'AIServices',

    [Parameter()]
    [switch]$Cleanup
)

# ----------------------------------------------------------------------------
# Helpers (glyphs carry meaning, not color alone -- accessible reading)
# ----------------------------------------------------------------------------
function Write-Section {
    param([string]$Title)
    $bar = ('=' * 78)
    Write-Host ''
    Write-Host $bar -ForegroundColor Cyan
    Write-Host (' ' + $Title) -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan
}

function Write-Status {
    param(
        [ValidateSet('OK', 'SKIP', 'WAIT', 'FAIL')][string]$Kind,
        [string]$Message
    )
    $glyph, $color = switch ($Kind) {
        'OK'   { '[ OK ]', 'Green'  }
        'SKIP' { '[SKIP]', 'Yellow' }
        'WAIT' { '[WAIT]', 'Cyan'   }
        'FAIL' { '[FAIL]', 'Red'    }
    }
    Write-Host "$glyph $Message" -ForegroundColor $color
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Args)
    $raw = & az @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Args -join ' ') failed: $raw"
    }
    return $raw
}

# ----------------------------------------------------------------------------
# Prerequisite checks
# ----------------------------------------------------------------------------
Write-Section 'Prerequisite checks'

$azVersion = & az version --output tsv 2>$null | Select-Object -First 1
if (-not $azVersion) {
    Write-Status FAIL 'Azure CLI not found. Install: https://aka.ms/azurecli'
    exit 1
}
Write-Status OK "Azure CLI present ($azVersion)"

try {
    $accountJson = & az account show --output json 2>$null
    if (-not $accountJson) { throw 'no session' }
    $acct = $accountJson | ConvertFrom-Json
} catch {
    Write-Status FAIL 'Not signed in. Run: az login'
    exit 1
}
Write-Status OK "Signed in as $($acct.user.name) -- subscription: $($acct.name)"

$rpState = ((Invoke-Az -Args @('provider','show','--namespace','Microsoft.CognitiveServices','--query','registrationState','-o','tsv')) -join '').Trim()
if ($rpState -ne 'Registered') {
    Write-Status WAIT 'Registering Microsoft.CognitiveServices provider...'
    Invoke-Az -Args @('provider','register','--namespace','Microsoft.CognitiveServices') | Out-Null
}
Write-Status OK 'Microsoft.CognitiveServices provider registered'

# ----------------------------------------------------------------------------
# Cleanup branch
# ----------------------------------------------------------------------------
if ($Cleanup) {
    Write-Section "Cleanup: deleting resource group $ResourceGroup"
    $exists = ((Invoke-Az -Args @('group','exists','--name',$ResourceGroup,'-o','tsv')) -join '').Trim()
    if ($exists -eq 'true') {
        if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Delete resource group')) {
            Invoke-Az -Args @('group','delete','--name',$ResourceGroup,'--yes','--no-wait') | Out-Null
            Write-Status OK 'Delete submitted (async). Resources gone in ~5-10 min.'
            Write-Status WAIT 'A kind=AIServices account soft-deletes; purge the name if you redeploy fast:'
            Write-Host "    az cognitiveservices account purge -g $ResourceGroup -n $LanguageName -l $Location" -ForegroundColor Gray
        }
    } else {
        Write-Status SKIP "Resource group $ResourceGroup does not exist -- nothing to delete."
    }
    return
}

# ----------------------------------------------------------------------------
# Resource group (idempotent)
# ----------------------------------------------------------------------------
Write-Section "Resource group: $ResourceGroup in $Location"

$exists = ((Invoke-Az -Args @('group','exists','--name',$ResourceGroup,'-o','tsv')) -join '').Trim()
if ($exists -eq 'true') {
    Write-Status SKIP 'Resource group already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Create resource group')) {
        Invoke-Az -Args @('group','create','--name',$ResourceGroup,'--location',$Location,'--output','none') | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Language (AIServices) account WITH custom subdomain -- required for keyless
# ----------------------------------------------------------------------------
Write-Section "Language resource: $LanguageName (kind=$Kind, S0, custom subdomain)"

$existingAcct = & az cognitiveservices account show `
    --resource-group $ResourceGroup --name $LanguageName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Language resource already exists.'
} else {
    # Idempotency across deploy -> cleanup -> deploy: a same-named account deleted
    # recently sits in a SOFT-DELETED state and blocks recreation (the custom-subdomain
    # reservation is GLOBAL). The ghost may be in a different region/RG, so purge it in
    # ITS original location, parsed from the deleted-account record -- NOT $Location.
    $ghost = & az cognitiveservices account list-deleted -o json 2>$null |
        ConvertFrom-Json | Where-Object { $_.name -eq $LanguageName } | Select-Object -First 1
    if ($ghost) {
        $ghostLoc = if ($ghost.location) { $ghost.location }
                    elseif ($ghost.id -match '/locations/([^/]+)') { $Matches[1] } else { $Location }
        $ghostRg  = if ($ghost.id -match '/resourceGroups/([^/]+)') { $Matches[1] } else { $ResourceGroup }
        Write-Status WAIT "Purging soft-deleted $LanguageName in $ghostLoc (global subdomain reservation)..."
        & az cognitiveservices account purge --location $ghostLoc --resource-group $ghostRg --name $LanguageName --output none 2>$null
        Start-Sleep -Seconds 5
    }
    if ($PSCmdlet.ShouldProcess($LanguageName, "Create $Kind account")) {
        Write-Status WAIT "Creating $LanguageName (this can take 30-60s)..."
        # --custom-domain makes the endpoint https://<name>.cognitiveservices.azure.com,
        # which is what Microsoft Entra (keyless) auth requires. Without it the
        # resource gets a regional endpoint that rejects token auth.
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--resource-group', $ResourceGroup,
            '--name', $LanguageName,
            '--kind', $Kind,
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $LanguageName,
            '--yes',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Language resource created with custom subdomain.'
    }
}

# ----------------------------------------------------------------------------
# RBAC: Cognitive Services User on the resource (keyless data-plane access)
# ----------------------------------------------------------------------------
# TextAnalyticsClient + DefaultAzureCredential picks up your az-login token.
# That token needs the data-plane "Cognitive Services User" role on this
# resource for analyze/summarize calls to succeed. Subscription Owner does
# NOT implicitly grant it -- the keyless RBAC trap.
Write-Section 'RBAC: Cognitive Services User on the Language resource'

$signedInOid = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$scope = "/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$LanguageName"
$existingRole = (Invoke-Az -Args @('role','assignment','list',
    '--assignee', $signedInOid, '--scope', $scope,
    '--role', 'Cognitive Services User',
    '--query', '[].id', '-o', 'tsv')) -join ''
if ([string]::IsNullOrWhiteSpace($existingRole)) {
    if ($PSCmdlet.ShouldProcess($scope, 'Assign Cognitive Services User')) {
        Invoke-Az -Args @(
            'role','assignment','create',
            '--assignee', $signedInOid,
            '--role', 'Cognitive Services User',
            '--scope', $scope,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Cognitive Services User role assigned to signed-in user.'
        Write-Status WAIT 'Role assignment can take up to 5 minutes to propagate (exam-favorite gotcha).'
    }
} else {
    Write-Status SKIP 'Role assignment already in place.'
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------
Write-Section 'Collecting deployment metadata'

$endpoint = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$LanguageName,'--query','properties.endpoint','-o','tsv')) -join ''

# ----------------------------------------------------------------------------
# Smoke test: KEYLESS sentiment call over REST (proves the token path works)
# ----------------------------------------------------------------------------
# We deliberately do NOT list a key here. We fetch a data-plane Entra token the
# same way DefaultAzureCredential would, then call the Language analyze-text
# endpoint with it. If this returns sentiment, the keyless path is good.
Write-Section 'Smoke test: keyless sentiment call (Entra token, no key)'

$token = (& az account get-access-token --resource 'https://cognitiveservices.azure.com' --query accessToken -o tsv 2>$null)
if (-not $token) {
    Write-Status FAIL 'Could not acquire a Cognitive Services access token.'
} else {
    $body = @{
        kind = 'SentimentAnalysis'
        parameters = @{ opinionMining = $true }
        analysisInput = @{ documents = @(@{ id = '1'; language = 'en'; text = 'The crew was wonderful but the Wi-Fi was terrible.' }) }
    } | ConvertTo-Json -Depth 10
    $uri = "${endpoint}language/:analyze-text?api-version=2024-11-01"
    # RBAC was assigned seconds ago and can take a few minutes to propagate, so a
    # fresh deploy often 401/403s on the first attempt. Retry a few times so the
    # happy path lands on [ OK ] instead of a scary [WAIT].
    $smokeOk = $false
    for ($attempt = 1; $attempt -le 4 -and -not $smokeOk; $attempt++) {
        try {
            $resp = Invoke-RestMethod -Method POST -Uri $uri `
                -Headers @{ 'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' } `
                -Body $body -ErrorAction Stop
            $sentiment = $resp.results.documents[0].sentiment
            Write-Status OK "Keyless smoke test passed (HTTP 200; document sentiment: $sentiment)."
            $smokeOk = $true
        } catch {
            if ($attempt -lt 4) {
                Write-Status WAIT "Attempt $attempt got: $($_.Exception.Message). Waiting 20s for RBAC to propagate..."
                Start-Sleep -Seconds 20
            } else {
                Write-Status WAIT "Keyless call still failing after $attempt attempts: $($_.Exception.Message)"
                Write-Status WAIT 'If 401/403, RBAC is still propagating (up to 5 min) -- re-run the script; it is idempotent.'
            }
        }
    }
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------
Write-Section 'Deployment complete'

$result = [pscustomobject]@{
    ResourceGroup     = $ResourceGroup
    Region            = $Location
    LanguageResource  = $LanguageName
    Kind              = $Kind
    LanguageEndpoint  = $endpoint
    AuthPattern       = 'Keyless (DefaultAzureCredential) -- Cognitive Services User role'
    PortalUrl         = "https://portal.azure.com/#resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/overview"
}
$result | Format-List

Write-Host ''
Write-Host 'Paste into lessons\lesson-13\demo\.env BEFORE running the scripts:' -ForegroundColor Cyan
Write-Host "  LANGUAGE_ENDPOINT=$endpoint" -ForegroundColor Gray
Write-Host '  (No key line -- Lesson 13 is keyless. The credential chain uses your az login token.)' -ForegroundColor Gray
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  SDK scripts:  cd lessons\lesson-13\demo' -ForegroundColor Gray
Write-Host '                python -m venv .venv && .venv\Scripts\Activate.ps1' -ForegroundColor Gray
Write-Host '                pip install -r requirements.txt' -ForegroundColor Gray
Write-Host '                python lesson-13-text-analytics.py' -ForegroundColor Gray
Write-Host '                python lesson-13-pii-summary.py' -ForegroundColor Gray
Write-Host '  Web app:      See lessons\lesson-13\demo\webapp\  (built by a companion script)' -ForegroundColor Gray
Write-Host '  Cleanup:      .\Deploy-Lesson13-Infrastructure.ps1 -Cleanup' -ForegroundColor Gray
Write-Host ''

return $result
