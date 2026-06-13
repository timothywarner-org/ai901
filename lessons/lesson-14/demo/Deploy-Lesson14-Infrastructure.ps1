#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions the Azure infrastructure for AI-901 Lesson 14 --
    Build a Speech-Enabled Application with Azure Speech in Foundry Tools.

.DESCRIPTION
    Lesson 14 is a Python voice app: microphone -> speech-to-text -> Foundry
    chat model -> text-to-speech -> speaker. It needs ONE multi-service Foundry
    resource (kind=AIServices) that exposes BOTH the Speech data-plane (STT/TTS)
    AND a gpt-4o chat deployment for the reasoning hop.

    KEYLESS, CUSTOM SUBDOMAIN. The Speech SDK's keyless auth (DefaultAzureCredential)
    requires a CUSTOM SUBDOMAIN endpoint -- a regional endpoint rejects token auth.
    --custom-domain gives us https://<name>.cognitiveservices.azure.com.

    Resources provisioned in rg-ai901-lesson14-demo (swedencentral by default):

      * ai901-lesson14-foundry  -- AIServices resource (S0) with custom subdomain.
                                   Exposes Speech (STT + TTS) and Azure OpenAI.
                                   NOTE: this name must be globally unique --
                                   append a short suffix if needed, e.g.
                                   ai901-lesson14-foundry-abc123.
      * gpt-4o deployment       -- GlobalStandard (450k TPM headroom) for the
                                   reasoning hop.
      * RBAC: "Cognitive Services User" to the signed-in identity. This BROAD
        data-plane role covers BOTH Speech (STT/TTS) AND OpenAI (chat) keyless
        calls -- "Cognitive Services Speech User" alone would NOT let the model
        call succeed, which is the trap to avoid.

    Auth: KEYLESS for both Speech and the chat call. The deploy outputs the
    custom-domain endpoint, the region, and the resource ID (the TTS synthesizer
    needs the resource ID for its aad#{resourceId}#{token} authorization token).

    Cost: < $0.50 per session.

.PARAMETER ResourceGroup
    Resource group. Default: rg-ai901-lesson14-demo.

.PARAMETER Location
    Azure region. Default: swedencentral (Speech + gpt-4o GlobalStandard, quiet quota).

.PARAMETER FoundryName
    AIServices account name (also the custom subdomain). Default: ai901-lesson14-foundry.
    NOTE: must be globally unique -- append a short suffix if needed.

.PARAMETER ChatDeploymentName
    gpt-4o chat deployment for the reasoning hop. Default: gpt-4o.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.EXAMPLE
    .\Deploy-Lesson14-Infrastructure.ps1
    Provisions the resource, gpt-4o, RBAC; prints the .env values.

.EXAMPLE
    .\Deploy-Lesson14-Infrastructure.ps1 -Cleanup

.NOTES
    Verified: 2026-06-11 against MS Learn "Configure Microsoft Entra auth for
    Speech" (SpeechConfig token_credential for STT; aad# auth_token for TTS),
    and the az cognitiveservices model catalog
    (gpt-4o 2024-11-20 GlobalStandard in Sweden Central).
    GUI fallback: Azure portal -> + Create -> Azure AI services; then IAM ->
    Add role assignment -> Cognitive Services User.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson14-demo',

    [Parameter()]
    # Quiet, quota-friendly regions that support BOTH Speech and gpt-4o GlobalStandard
    # (checked 2026-06-11). East US 2 was capacity-congested for gpt-4o.
    [ValidateSet('swedencentral', 'eastus2', 'westus2', 'japaneast', 'southindia')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    # Must be globally unique -- append a short suffix if the default name is already taken.
    [string]$FoundryName = 'ai901-lesson14-foundry',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

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
            Write-Host "    az cognitiveservices account purge -g $ResourceGroup -n $FoundryName -l $Location" -ForegroundColor Gray
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
# AIServices (Speech + OpenAI) account WITH custom subdomain -- keyless needs it
# ----------------------------------------------------------------------------
Write-Section "Foundry/Speech resource: $FoundryName (kind=AIServices, S0, custom subdomain)"

$existingAcct = & az cognitiveservices account show `
    --resource-group $ResourceGroup --name $FoundryName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Resource already exists.'
} else {
    # Idempotency across deploy -> cleanup -> deploy: purge a soft-deleted ghost in
    # ITS own region first (the custom-subdomain reservation is GLOBAL).
    $ghost = & az cognitiveservices account list-deleted -o json 2>$null |
        ConvertFrom-Json | Where-Object { $_.name -eq $FoundryName } | Select-Object -First 1
    if ($ghost) {
        $ghostLoc = if ($ghost.location) { $ghost.location }
                    elseif ($ghost.id -match '/locations/([^/]+)') { $Matches[1] } else { $Location }
        $ghostRg  = if ($ghost.id -match '/resourceGroups/([^/]+)') { $Matches[1] } else { $ResourceGroup }
        if ($PSCmdlet.ShouldProcess($FoundryName, "Purge soft-deleted ghost in $ghostLoc")) {
            Write-Status WAIT "Purging soft-deleted $FoundryName in $ghostLoc (global subdomain reservation)..."
            & az cognitiveservices account purge --location $ghostLoc --resource-group $ghostRg --name $FoundryName --output none 2>$null
            Start-Sleep -Seconds 5
        }
    }
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Create AIServices account')) {
        Write-Status WAIT "Creating $FoundryName (this can take 30-60s)..."
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--resource-group', $ResourceGroup,
            '--name', $FoundryName,
            '--kind', 'AIServices',
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $FoundryName,
            '--yes',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'AIServices resource created with custom subdomain.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: gpt-4o (GlobalStandard) for the reasoning hop
# ----------------------------------------------------------------------------
$ChatModelName = 'gpt-4o'
$ChatModelVersion = '2024-11-20'   # GA, broadly available

Write-Section "Model deployment: $ChatDeploymentName -> $ChatModelName ($ChatModelVersion, GlobalStandard)"

$existingChat = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ChatDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingChat) {
    Write-Status SKIP 'Chat deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ChatDeploymentName, "Create $ChatModelName deployment")) {
        Write-Status WAIT "Creating $ChatDeploymentName -> $ChatModelName (30-90s)..."
        $deployOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ChatDeploymentName `
            --model-name $ChatModelName `
            --model-version $ChatModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity 10 `
            --sku-name 'GlobalStandard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Chat deployment failed: $deployOutput"
            Write-Host "Most likely cause: gpt-4o GlobalStandard capacity/quota in $Location." -ForegroundColor Yellow
            Write-Host '  Quick fix: re-run with -Location japaneast or southindia.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat deployment created.'
    }
}

# ----------------------------------------------------------------------------
# RBAC: Cognitive Services User (covers BOTH Speech STT/TTS AND OpenAI chat)
# ----------------------------------------------------------------------------
# The kiosk makes Speech calls (STT/TTS) AND an OpenAI chat call, both keyless.
# "Cognitive Services User" is the broad data-plane role that grants both. The
# narrower "Cognitive Services Speech User" would block the chat call.
Write-Section 'RBAC: Cognitive Services User on the resource (Speech + OpenAI)'

$signedInOid = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$scope = "/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryName"
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
Write-Section 'Deployment complete'

$endpoint = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$resourceId = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','id','-o','tsv')) -join ''
$aoaiEndpoint = ($endpoint.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','openai.azure.com') + '/'

$result = [pscustomobject]@{
    ResourceGroup     = $ResourceGroup
    Region            = $Location
    Resource          = $FoundryName
    SpeechEndpoint    = $endpoint
    AoaiEndpoint      = $aoaiEndpoint
    ChatDeployment    = $ChatDeploymentName
    ResourceId        = $resourceId
    AuthPattern       = 'Keyless (DefaultAzureCredential) -- Cognitive Services User'
    PortalUrl         = "https://portal.azure.com/#resource$resourceId/overview"
}
$result | Format-List

Write-Host ''
Write-Host 'Paste into lessons\lesson-14\demo\.env BEFORE running the script:' -ForegroundColor Cyan
Write-Host "  SPEECH_ENDPOINT=$endpoint" -ForegroundColor Gray
Write-Host "  SPEECH_REGION=$Location" -ForegroundColor Gray
Write-Host "  SPEECH_RESOURCE_ID=$resourceId" -ForegroundColor Gray
Write-Host "  AOAI_ENDPOINT=$aoaiEndpoint" -ForegroundColor Gray
Write-Host "  AOAI_DEPLOYMENT=$ChatDeploymentName" -ForegroundColor Gray
Write-Host '  AOAI_API_VERSION=2024-10-21' -ForegroundColor Gray
Write-Host '  (No keys -- L14 is keyless. STT uses token_credential; TTS uses aad#{resourceId}#{token}.)' -ForegroundColor Gray
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  cd lessons\lesson-14\demo' -ForegroundColor Gray
Write-Host '  python -m venv .venv && .venv\Scripts\Activate.ps1' -ForegroundColor Gray
Write-Host '  pip install -r requirements.txt' -ForegroundColor Gray
Write-Host '  python lesson-14-voice-kiosk.py   (mic + speaker required)' -ForegroundColor Gray
Write-Host '  Cleanup: .\Deploy-Lesson14-Infrastructure.ps1 -Cleanup' -ForegroundColor Gray
Write-Host ''

return $result
