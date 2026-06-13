#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions the Azure infrastructure for AI-901 Lesson 15 --
    Use Vision and Image Generation with Azure OpenAI in Foundry Tools.

.DESCRIPTION
    Lesson 15 has two halves that share ONE multi-service Foundry resource:

      * Vision understanding -- a gpt-4o (vision-capable) chat deployment reads an
        uploaded image and describes / reasons over it (the "see" half).
      * Image generation -- a gpt-image-2 deployment turns a text prompt into a
        brand-new image (the "create" half).

    Both halves are Azure OpenAI data-plane calls, so a SINGLE AIServices resource
    (kind=AIServices) with a CUSTOM SUBDOMAIN endpoint serves both. Keyless auth
    (DefaultAzureCredential) requires that custom subdomain -- a bare regional
    endpoint rejects Entra token auth -- so we pass --custom-domain.

    Resources provisioned in rg-ai901-lesson15-demo (Sweden Central by default):

      * ai901-lesson15-foundry  -- AIServices resource (S0) with custom subdomain.
                                   Exposes Azure OpenAI (chat + images).
                                   NOTE: change this name to something globally
                                   unique -- AIServices custom subdomains are a
                                   global namespace across all Azure tenants.
      * gpt-4o    deployment    -- GlobalStandard, capacity 10. Vision-capable
                                   chat model for the understanding half.
      * gpt-image-2 deployment  -- GlobalStandard, capacity 1. Image generation
                                   model (GA, no registration). Default quota is
                                   only 5 images/min, so capacity stays modest.
      * RBAC: "Cognitive Services OpenAI User" to the signed-in identity on the
        account scope. This data-plane role covers BOTH the gpt-4o vision chat AND
        the gpt-image-2 image-gen calls -- both are Azure OpenAI data-plane, so one
        role is enough. Keyless throughout (DefaultAzureCredential).

    Auth: KEYLESS for both halves. The deploy outputs the openai.azure.com-form
    endpoint, the two deployment names, the API versions, and the resource ID. No
    keys are emitted -- L15 follows the keyless pattern end to end.

    The image-model deployment is treated as NON-FATAL: if it fails for quota or
    region, the script prints a WARN with an actionable re-run hint and CONTINUES,
    so the vision half still comes up GREEN.

    Cost: a few cents per session (a handful of chat + image calls).

.PARAMETER ResourceGroup
    Resource group. Default: rg-ai901-lesson15-demo.

.PARAMETER Location
    Azure region. Default: swedencentral. ValidateSet is restricted to regions
    confirmed (2026-06-11) to offer BOTH gpt-4o GlobalStandard AND gpt-image-2
    GlobalStandard.

.PARAMETER FoundryName
    AIServices account name (also the custom subdomain). Default: ai901-lesson15-foundry.
    IMPORTANT: AIServices custom subdomains are a GLOBAL namespace -- choose a name
    unique across all Azure tenants (e.g. add your initials or a random suffix).

.PARAMETER VisionDeploymentName
    gpt-4o vision-capable chat deployment for the understanding half. Default: gpt-4o.

.PARAMETER ImageDeploymentName
    gpt-image-2 deployment for the image-generation half. Default: gpt-image-2.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.EXAMPLE
    .\Deploy-Lesson15-Infrastructure.ps1 -FoundryName my-ai901-l15-foundry
    Provisions the resource, gpt-4o, gpt-image-2, RBAC; prints the .env values.

.EXAMPLE
    .\Deploy-Lesson15-Infrastructure.ps1 -FoundryName my-ai901-l15-foundry -Location westus3
    Same, but in West US 3 (fallback if Sweden Central is quota-congested).

.EXAMPLE
    .\Deploy-Lesson15-Infrastructure.ps1 -FoundryName my-ai901-l15-foundry -Cleanup

.NOTES
    Verified: 2026-06-11 against MS Learn "How to use Azure OpenAI image
    generation models" (gpt-image-2 is GA, default quota 5 images/min, deployed
    with --model-format OpenAI like any OpenAI model) and the Azure OpenAI preview
    REST reference (image generations use api-version 2025-04-01-preview; chat
    data plane uses 2024-10-21). gpt-4o 2024-11-20 GlobalStandard confirmed in
    Sweden Central via the az cognitiveservices model catalog.
    GUI fallback: Azure portal -> + Create -> Azure AI services; deploy gpt-4o and
    gpt-image-2 from the Foundry portal's Deployments blade; then IAM -> Add role
    assignment -> Cognitive Services OpenAI User.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson15-demo',

    [Parameter()]
    # Regions confirmed 2026-06-11 to offer BOTH gpt-4o GlobalStandard AND
    # gpt-image-2 GlobalStandard. Sweden Central is the quiet, quota-friendly default.
    [ValidateSet('swedencentral', 'eastus2', 'westus3', 'uaenorth', 'polandcentral')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson15-foundry',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$VisionDeploymentName = 'gpt-4o',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ImageDeploymentName = 'gpt-image-2',

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
        [ValidateSet('OK', 'SKIP', 'WAIT', 'FAIL', 'WARN')][string]$Kind,
        [string]$Message
    )
    # Glyphs (not color alone) carry the status meaning so a red/green-colorblind
    # reader -- or anyone on a mono terminal -- gets the same signal.
    $glyph, $color = switch ($Kind) {
        'OK'   { '[ OK ]', 'Green'   }
        'SKIP' { '[SKIP]', 'Yellow'  }
        'WAIT' { '[WAIT]', 'Cyan'    }
        'WARN' { '[WARN]', 'Yellow'  }
        'FAIL' { '[FAIL]', 'Red'     }
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
# AIServices (Azure OpenAI) account WITH custom subdomain -- keyless needs it
# ----------------------------------------------------------------------------
Write-Section "Foundry resource: $FoundryName (kind=AIServices, S0, custom subdomain)"

$existingAcct = & az cognitiveservices account show `
    --resource-group $ResourceGroup --name $FoundryName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Resource already exists.'
} else {
    # Idempotency across deploy -> cleanup -> deploy: purge a soft-deleted ghost in
    # ITS own region first (the custom-subdomain reservation is GLOBAL, so a ghost
    # blocks recreation even in a different region). Null-safe + region-aware.
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
# Model deployment 1: gpt-4o (GlobalStandard) -- vision-capable chat (the "see" half)
# ----------------------------------------------------------------------------
$VisionModelName = 'gpt-4o'
$VisionModelVersion = '2024-11-20'   # GA, vision-capable, broadly available

Write-Section "Model deployment: $VisionDeploymentName -> $VisionModelName ($VisionModelVersion, GlobalStandard)"

$existingVision = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $VisionDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingVision) {
    Write-Status SKIP 'Vision deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($VisionDeploymentName, "Create $VisionModelName deployment")) {
        Write-Status WAIT "Creating $VisionDeploymentName -> $VisionModelName (30-90s)..."
        $visionOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $VisionDeploymentName `
            --model-name $VisionModelName `
            --model-version $VisionModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity 10 `
            --sku-name 'GlobalStandard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            # The vision half IS the lesson's spine -- if it cannot deploy, stop.
            Write-Status FAIL "Vision deployment failed: $visionOutput"
            Write-Host "Most likely cause: gpt-4o GlobalStandard capacity/quota in $Location." -ForegroundColor Yellow
            Write-Host '  Quick fix: re-run with -Location westus3 or -Location eastus2.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Vision (gpt-4o) deployment created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment 2: gpt-image-2 (GlobalStandard) -- image generation (the "create" half)
# ----------------------------------------------------------------------------
# gpt-image-2 is GA (no registration). It deploys with the SAME flags as any
# OpenAI-format model: --model-format OpenAI --sku-name GlobalStandard. Default
# image quota is only 5 images/min, so capacity stays at 1 (one unit = headroom
# well above self-study needs). This deployment is NON-FATAL: a quota/region failure
# WARNs and continues so the vision half still works.
$ImageModelName = 'gpt-image-2'
$ImageModelVersion = '2026-04-21'    # GA image-generation model version

# Track whether the image half came up, so the .env summary can be honest.
$ImageDeployed = $false

Write-Section "Model deployment: $ImageDeploymentName -> $ImageModelName ($ImageModelVersion, GlobalStandard)"

$existingImage = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ImageDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingImage) {
    Write-Status SKIP 'Image deployment already exists.'
    $ImageDeployed = $true
} else {
    if ($PSCmdlet.ShouldProcess($ImageDeploymentName, "Create $ImageModelName deployment")) {
        Write-Status WAIT "Creating $ImageDeploymentName -> $ImageModelName (30-90s)..."
        $imageOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ImageDeploymentName `
            --model-name $ImageModelName `
            --model-version $ImageModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity 1 `
            --sku-name 'GlobalStandard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            # NON-FATAL on purpose: the vision half is already GREEN. WARN with an
            # actionable hint and KEEP GOING.
            Write-Status WARN "Image deployment failed -- continuing without it: $imageOutput"
            Write-Host "Most likely cause: gpt-image-2 GlobalStandard quota/region in $Location." -ForegroundColor Yellow
            Write-Host '  Quick fix: re-run with -Location westus3 (also -uaenorth or -polandcentral offer gpt-image-2).' -ForegroundColor Yellow
            Write-Host '  The vision (gpt-4o) half above is already live -- you can use that now.' -ForegroundColor Yellow
        } else {
            Write-Status OK 'Image (gpt-image-2) deployment created.'
            $ImageDeployed = $true
        }
    }
}

# ----------------------------------------------------------------------------
# RBAC: Cognitive Services OpenAI User (covers BOTH gpt-4o chat AND gpt-image-2)
# ----------------------------------------------------------------------------
# Both halves are Azure OpenAI data-plane calls (chat/completions and
# images/generations). "Cognitive Services OpenAI User" is the single data-plane
# role that grants both -- no second role needed. Keyless (DefaultAzureCredential).
Write-Section 'RBAC: Cognitive Services OpenAI User on the resource (vision + image gen)'

$signedInOid = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$scope = "/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryName"
$existingRole = (Invoke-Az -Args @('role','assignment','list',
    '--assignee', $signedInOid, '--scope', $scope,
    '--role', 'Cognitive Services OpenAI User',
    '--query', '[].id', '-o', 'tsv')) -join ''
if ([string]::IsNullOrWhiteSpace($existingRole)) {
    if ($PSCmdlet.ShouldProcess($scope, 'Assign Cognitive Services OpenAI User')) {
        Invoke-Az -Args @(
            'role','assignment','create',
            '--assignee', $signedInOid,
            '--role', 'Cognitive Services OpenAI User',
            '--scope', $scope,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Cognitive Services OpenAI User role assigned to signed-in user.'
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
# Azure OpenAI data-plane SDKs expect the openai.azure.com endpoint form, not the
# cognitiveservices.azure.com custom-domain form. Rewrite it for the .env.
$aoaiEndpoint = ($endpoint.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','openai.azure.com') + '/'

# API versions (grounded 2026-06-11):
#   - Chat/vision data plane: 2024-10-21 (GA).
#   - Image generations:      2025-04-01-preview (preview API that supports the
#     gpt-image deployment-based images/generations route).
$AoaiApiVersion = '2024-10-21'
$AoaiImageApiVersion = '2025-04-01-preview'

$result = [pscustomobject]@{
    SubscriptionId      = '<your-subscription-id>'
    ResourceGroup       = $ResourceGroup
    Region              = $Location
    Resource            = $FoundryName
    AoaiEndpoint        = $aoaiEndpoint
    VisionDeployment    = $VisionDeploymentName
    ImageDeployment     = if ($ImageDeployed) { $ImageDeploymentName } else { '(NOT deployed -- see WARN above)' }
    ApiVersion          = $AoaiApiVersion
    ImageApiVersion     = $AoaiImageApiVersion
    AuthPattern         = 'Keyless (DefaultAzureCredential) -- Cognitive Services OpenAI User'
}
$result | Format-List

Write-Host ''
Write-Host 'Paste into your demo\.env BEFORE running the scripts:' -ForegroundColor Cyan
Write-Host "  AOAI_ENDPOINT=$aoaiEndpoint" -ForegroundColor Gray
Write-Host "  AOAI_VISION_DEPLOYMENT=$VisionDeploymentName" -ForegroundColor Gray
Write-Host "  AOAI_IMAGE_DEPLOYMENT=$ImageDeploymentName" -ForegroundColor Gray
Write-Host "  AOAI_API_VERSION=$AoaiApiVersion" -ForegroundColor Gray
Write-Host "  AOAI_IMAGE_API_VERSION=$AoaiImageApiVersion" -ForegroundColor Gray
Write-Host "  AOAI_RESOURCE_ID=$resourceId" -ForegroundColor Gray
Write-Host '  (No keys -- L15 is keyless. Both halves use DefaultAzureCredential.)' -ForegroundColor Gray
if (-not $ImageDeployed) {
    Write-Host ''
    Write-Status WARN 'Image deployment is NOT live -- the image-gen half will fail until you re-run (see hint above).'
}
Write-Host ''
Write-Host 'Next: python lesson-15-vision-inspect.py ./samples/bracket-crack.png' -ForegroundColor Cyan

return $result
