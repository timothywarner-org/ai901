#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions the Azure infrastructure for AI-901 Lesson 16 --
    Extract structured data from documents, images, audio, and video with
    Azure AI Content Understanding (Foundry Tool, GA API 2025-11-01).

.DESCRIPTION
    Lesson 16's headline service is Azure AI Content Understanding (CU): ONE
    multimodal service that extracts structured content from FOUR modalities --
    documents, images, audio, and video -- through one client and one analyze
    call. CU is a Foundry Tool that lives ON an AIServices (kind=AIServices)
    resource; there is NO separate "Content Understanding" resource type and NO
    separate CU model deployment.

    BUT prebuilt analyzers are NOT free-standing. They run on top of large-
    language-model deployments YOU bring on the same resource, plus a one-time
    "default model mapping" that points the analyzers at those deployments
    (grounded on MS Learn "Content Understanding client library -- Configure
    model deployments", 2026-06). Specifically:

      * prebuilt-documentSearch / imageSearch / audioSearch / videoSearch
          require  gpt-4.1-mini  + text-embedding-3-large
      * prebuilt-invoice / receipt / other field analyzers
          require  gpt-4.1       + text-embedding-3-large

    So this script deploys ALL THREE models (gpt-4.1, gpt-4.1-mini,
    text-embedding-3-large) so every analyzer the SDK client routes to works,
    then prints the one-time default-mapping command the SDK exposes (there is
    no az CLI for the mapping -- it is a data-plane SDK call, so we hand it to
    you as a copy-paste step).

    Resources provisioned in rg-ai901-lesson16-demo (Sweden Central by default):

      * ai901-lesson16-foundry      -- AIServices resource (S0) with a CUSTOM
                                       SUBDOMAIN. Keyless auth requires the
                                       custom subdomain -- a bare regional
                                       endpoint rejects Entra token auth -- so
                                       we pass --custom-domain.
                                       NOTE: change this name to something
                                       globally unique -- AIServices custom
                                       subdomains are a global namespace.
      * gpt-4.1               deployment -- GlobalStandard. Backs prebuilt-invoice
                                            and the other field analyzers.
      * gpt-4.1-mini          deployment -- GlobalStandard. Backs the *Search
                                            (RAG) analyzers.
      * text-embedding-3-large deployment -- Standard. Embeddings for every
                                             prebuilt analyzer.
      * RBAC: "Cognitive Services User" to the signed-in identity on the account
        scope. This is the BROAD data-plane role CU requires (it is the role MS
        Learn names for configuring model deployments AND calling analyzers).
        Keyless throughout (DefaultAzureCredential).

    Auth: KEYLESS. The deploy outputs CU_ENDPOINT (the services.ai.azure.com
    resource endpoint the CU SDK expects), the resource ID, and the API version.
    No keys are emitted -- L16 follows the keyless pattern end to end.

    Cost: a few cents per session (a handful of analyze calls).

.PARAMETER ResourceGroup
    Resource group. Default: rg-ai901-lesson16-demo.

.PARAMETER Location
    Azure region. Default: swedencentral. ValidateSet is restricted to regions
    confirmed (2026-06-12 against MS Learn "Content Understanding region and
    language support") to offer Content Understanding GA.

.PARAMETER FoundryName
    AIServices account name (also the custom subdomain). Default: ai901-lesson16-foundry.
    IMPORTANT: AIServices custom subdomains are a GLOBAL namespace -- choose a name
    unique across all Azure tenants (e.g. add your initials or a random suffix).

.PARAMETER ChatDeploymentName
    gpt-4.1 deployment (field analyzers, e.g. prebuilt-invoice). Default: gpt-4.1.

.PARAMETER MiniDeploymentName
    gpt-4.1-mini deployment (the *Search RAG analyzers). Default: gpt-4.1-mini.

.PARAMETER EmbeddingDeploymentName
    text-embedding-3-large deployment (all analyzers). Default: text-embedding-3-large.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.EXAMPLE
    .\Deploy-Lesson16-Infrastructure.ps1 -FoundryName my-ai901-l16-foundry
    Provisions the resource, the three model deployments, RBAC; prints the
    .env values and the one-time default-mapping command.

.EXAMPLE
    .\Deploy-Lesson16-Infrastructure.ps1 -FoundryName my-ai901-l16-foundry -Location westus
    Same, but in West US (a CU GA region; use if Sweden Central is congested).

.EXAMPLE
    .\Deploy-Lesson16-Infrastructure.ps1 -FoundryName my-ai901-l16-foundry -Cleanup

.NOTES
    Verified: 2026-06-12 against MS Learn "Azure AI Content Understanding client
    library for Python 1.1.0" (GA API 2025-11-01; prebuilt analyzers require
    gpt-4.1 / gpt-4.1-mini / text-embedding-3-large deployments plus a one-time
    default mapping; data-plane role = Cognitive Services User) and "Content
    Understanding region and language support" (GA regions include swedencentral,
    westus, eastus2, australiaeast, eastus, japaneast, northeurope,
    southcentralus, southeastasia, uksouth, westeurope, westus3).
    GUI fallback: Azure portal -> + Create -> Azure AI services (custom subdomain);
    deploy gpt-4.1, gpt-4.1-mini, text-embedding-3-large from the Foundry portal
    Deployments blade; configure CU default model mappings in the Foundry portal
    (Content Understanding -> Settings) or via sample_update_defaults.py; then
    IAM -> Add role assignment -> Cognitive Services User.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson16-demo',

    [Parameter()]
    # Regions confirmed 2026-06-12 to offer Content Understanding GA (per the MS
    # Learn region table). Sweden Central is the quiet, quota-friendly default.
    [ValidateSet('swedencentral', 'westus', 'eastus2', 'eastus', 'australiaeast',
                 'japaneast', 'northeurope', 'southcentralus', 'southeastasia',
                 'uksouth', 'westeurope', 'westus3')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson16-foundry',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4.1',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,64}$')]
    [string]$MiniDeploymentName = 'gpt-4.1-mini',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,64}$')]
    [string]$EmbeddingDeploymentName = 'text-embedding-3-large',

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

# Deploy one model (idempotent + non-fatal on quota/region). WHY a helper: we
# deploy THREE models with identical logic, so a function keeps the script DRY
# and the per-model failure handling consistent. Returns $true on success.
function Deploy-Model {
    param(
        [Parameter(Mandatory)][string]$DeploymentName,
        [Parameter(Mandatory)][string]$ModelName,
        [Parameter(Mandatory)][string]$ModelVersion,
        [Parameter(Mandatory)][string]$SkuName,
        [Parameter(Mandatory)][int]$SkuCapacity
    )
    Write-Section "Model deployment: $DeploymentName -> $ModelName ($ModelVersion, $SkuName)"

    # Existence guard -- redeploys are a no-op, never a duplicate.
    $existing = & az cognitiveservices account deployment show `
        --resource-group $ResourceGroup --name $FoundryName `
        --deployment-name $DeploymentName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Write-Status SKIP "Deployment '$DeploymentName' already exists."
        return $true
    }

    if ($PSCmdlet.ShouldProcess($DeploymentName, "Create $ModelName deployment")) {
        Write-Status WAIT "Creating $DeploymentName -> $ModelName (30-90s)..."
        $output = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $DeploymentName `
            --model-name $ModelName `
            --model-version $ModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity $SkuCapacity `
            --sku-name $SkuName `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            # NON-FATAL: a missing model deployment breaks only the analyzers that
            # need it, so WARN with an actionable hint and keep going. The summary
            # at the end reports which models actually came up.
            Write-Status WARN "Deployment '$DeploymentName' failed -- continuing: $output"
            Write-Host "Most likely cause: $ModelName $SkuName quota/region in $Location." -ForegroundColor Yellow
            Write-Host "  Quick fix: re-run with -Location westus or -Location eastus2 (both CU GA)." -ForegroundColor Yellow
            return $false
        }
        Write-Status OK "Deployment '$DeploymentName' created."
        return $true
    }
    # -WhatIf path: nothing created, report not-deployed so the summary is honest.
    return $false
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
# AIServices (Foundry) account WITH custom subdomain -- keyless + CU need it
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
# Model deployments -- the three models every prebuilt analyzer needs
# ----------------------------------------------------------------------------
# Content Understanding prebuilt analyzers run ON these deployments:
#   * gpt-4.1               -> field analyzers (prebuilt-invoice etc.)
#   * gpt-4.1-mini          -> the *Search RAG analyzers (document/image/audio/video)
#   * text-embedding-3-large -> embeddings for every analyzer
# Versions are pinned to the GA model versions current 2026-06-12. If a version
# is retired, the deploy WARNs (non-fatal) and names the fix.
$ChatDeployed      = Deploy-Model -DeploymentName $ChatDeploymentName      -ModelName 'gpt-4.1'                -ModelVersion '2025-04-14' -SkuName 'GlobalStandard' -SkuCapacity 10
$MiniDeployed      = Deploy-Model -DeploymentName $MiniDeploymentName      -ModelName 'gpt-4.1-mini'           -ModelVersion '2025-04-14' -SkuName 'GlobalStandard' -SkuCapacity 10
$EmbeddingDeployed = Deploy-Model -DeploymentName $EmbeddingDeploymentName -ModelName 'text-embedding-3-large' -ModelVersion '1'          -SkuName 'Standard'       -SkuCapacity 10

# ----------------------------------------------------------------------------
# RBAC: Cognitive Services User (the BROAD CU data-plane role)
# ----------------------------------------------------------------------------
# Content Understanding's data plane -- both configuring the default model
# mappings AND calling analyzers -- requires "Cognitive Services User" (per MS
# Learn). This is broader than the OpenAI-only role; it is the role CU names.
# Keyless throughout (DefaultAzureCredential).
Write-Section 'RBAC: Cognitive Services User on the resource (Content Understanding data plane)'

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
# The Content Understanding SDK expects the services.ai.azure.com resource
# endpoint form (the AIServices "Foundry" endpoint), not the bare
# cognitiveservices.azure.com custom-domain form. Rewrite it for CU_ENDPOINT.
$cuEndpoint = ($endpoint.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','services.ai.azure.com') + '/'

# API version (grounded 2026-06-12): Content Understanding GA = 2025-11-01.
$CuApiVersion = '2025-11-01'

$result = [pscustomobject]@{
    SubscriptionId         = '<your-subscription-id>'
    ResourceGroup          = $ResourceGroup
    Region                 = $Location
    Resource               = $FoundryName
    CuEndpoint             = $cuEndpoint
    CuApiVersion           = $CuApiVersion
    ChatDeployment         = if ($ChatDeployed)      { $ChatDeploymentName }      else { '(NOT deployed -- see WARN above)' }
    MiniDeployment         = if ($MiniDeployed)      { $MiniDeploymentName }      else { '(NOT deployed -- see WARN above)' }
    EmbeddingDeployment    = if ($EmbeddingDeployed) { $EmbeddingDeploymentName } else { '(NOT deployed -- see WARN above)' }
    AuthPattern            = 'Keyless (DefaultAzureCredential) -- Cognitive Services User'
}
$result | Format-List

Write-Host ''
Write-Host 'Paste into demo\.env BEFORE running the scripts:' -ForegroundColor Cyan
Write-Host "  CU_ENDPOINT=$cuEndpoint" -ForegroundColor Gray
Write-Host "  CU_API_VERSION=$CuApiVersion" -ForegroundColor Gray
Write-Host "  CU_RESOURCE_ID=$resourceId" -ForegroundColor Gray
Write-Host '  (No keys -- L16 is keyless. The CU SDK uses DefaultAzureCredential.)' -ForegroundColor Gray

Write-Host ''
Write-Status WAIT 'ONE-TIME default model mapping is still required before prebuilt analyzers work.'
Write-Host 'Content Understanding maps its analyzers to YOUR deployments via a data-plane' -ForegroundColor Yellow
Write-Host 'SDK call -- there is no az CLI for it. Run the SDK config sample once per resource:' -ForegroundColor Yellow
Write-Host "    set CONTENTUNDERSTANDING_ENDPOINT=$cuEndpoint" -ForegroundColor Gray
Write-Host "    set GPT_4_1_DEPLOYMENT=$ChatDeploymentName" -ForegroundColor Gray
Write-Host "    set GPT_4_1_MINI_DEPLOYMENT=$MiniDeploymentName" -ForegroundColor Gray
Write-Host "    set TEXT_EMBEDDING_3_LARGE_DEPLOYMENT=$EmbeddingDeploymentName" -ForegroundColor Gray
Write-Host '    python sample_update_defaults.py   # from the azure-ai-contentunderstanding samples' -ForegroundColor Gray
Write-Host '  (Or map them in the Foundry portal: Content Understanding -> Settings -> Default models.)' -ForegroundColor Yellow

if (-not ($ChatDeployed -and $MiniDeployed -and $EmbeddingDeployed)) {
    Write-Host ''
    Write-Status WARN 'One or more model deployments are NOT live -- the analyzers that need them will fail until you re-run (see hints above).'
}

Write-Host ''
Write-Host 'Next: python lesson-16-extract.py ./samples/fabrikam-invoice.pdf' -ForegroundColor Cyan

return $result
