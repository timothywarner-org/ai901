<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 07 demo --
    Information Extraction with Azure AI Content Understanding (GA, api-version 2025-11-01).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 07 covers Azure AI Content Understanding -- the GA successor to Azure AI
    Document Intelligence. The pitch is "one analyzer, four modalities" (document,
    image, audio, video) behind a single async POST-and-poll REST envelope.

    Resources provisioned in rg-ai901-lesson07-demo (East US):

      * ai901-lesson07-foundry   -- Foundry AIServices resource (S0). Content
                                     Understanding GA is a feature of the Foundry
                                     resource; there is NO separate "Content
                                     Understanding" resource kind to create.
      * ai901-lesson07-project   -- Foundry project (parity with the lesson series).
      * Three model deployments on the Foundry resource:
          - gpt-4.1               (Standard -- prebuilt-invoice, prebuilt-receipt)
          - gpt-4.1-mini          (Standard -- prebuilt-imageSearch, audioSearch,
                                              videoSearch)
          - text-embedding-3-large (GlobalStandard -- required by every generative
                                              analyzer)

    WHY three deployments (the GA gotcha):
    As of the 2025-11-01 GA, Content Understanding has no managed model capacity.
    Every prebuilt analyzer that does generative work calls YOUR model deployments.
    Per the CU client-library docs:
        prebuilt-invoice / prebuilt-receipt              -> gpt-4.1 + text-embedding-3-large
        prebuilt-imageSearch / audioSearch / videoSearch -> gpt-4.1-mini + text-embedding-3-large
    A bare AIServices resource without these deployments returns HTTP 400 "no model
    deployment configured" on the first analyzer call. This script deploys all three
    models AND writes the resource-level modelDeployments mapping so prebuilt analyzers
    resolve their model aliases without per-request overrides.

    IAM: the signed-in user is granted "Cognitive Services User" on the Foundry resource.
    Per the CU docs this role is required to configure model deployments and call analyzers
    even if you own the subscription -- Owner does not equal data-plane access here.

    Cost: < $0.50 per session. Foundry S0 + GlobalStandard model deployments are
    pay-per-call only -- no idle charges. CU extraction is per-page / per-minute,
    sub-cent for the prebuilt analyzers. Run -Cleanup promptly after practice.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson07-demo.

.PARAMETER Location
    Primary Azure region. East US is a GA Content Understanding region AND carries
    the gpt-4.1 family + text-embedding-3-large. Default: eastus.

.PARAMETER FoundryName
    Azure resource name for the Foundry account. Default: ai901-lesson07-foundry.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson07-project.

.PARAMETER ChatDeploymentName
    Name of the gpt-4.1 deployment (Standard CU analyzers). Default: gpt-4.1.

.PARAMETER MiniDeploymentName
    Name of the gpt-4.1-mini deployment (the Search RAG analyzers). Default: gpt-4.1-mini.

.PARAMETER EmbeddingDeploymentName
    Name of the text-embedding-3-large deployment. Default: text-embedding-3-large.

.PARAMETER ApiVersion
    Content Understanding REST api-version. Default: 2025-11-01 (GA).

.PARAMETER Cleanup
    Switch. Deletes the resource group and exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson07-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson07-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Author:        Tim Warner
    Created:       2026-05-31
    Tested:        PowerShell 7.4+ on Windows 11; Azure CLI 2.51+
    Cost estimate: < $0.50 per session.
    Requirements:  Azure CLI 2.51+, signed in (az login).

    Resource names default to "ai901-lessonNN-..." patterns. They must be globally
    unique in Azure. Use -FoundryName override if you hit a naming conflict.

    NOTE on "pro mode": multi-step cross-document reasoning ("pro mode") is
    preview-only (api-version 2025-05-01-preview) and was NOT included in GA
    2025-11-01. This script targets GA only. Beats 1, 3, and 4 of the lesson
    Steps 1, 3, and 4 run as documented; step 2 must use standard-mode confidence routing instead.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson07-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus3', 'northeurope',
                 'westeurope', 'swedencentral', 'southcentralus', 'australiaeast',
                 'japaneast', 'uksouth', 'southeastasia')]
    [string]$Location = 'eastus',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson07-foundry',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson07-project',

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
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ApiVersion = '2025-11-01',

    [Parameter()]
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Helpers
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
        'OK'   { '[ OK ]', 'Green'   }
        'SKIP' { '[SKIP]', 'Yellow'  }
        'WAIT' { '[WAIT]', 'Cyan'    }
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

# Deploys one OpenAI model on the Foundry resource (idempotent).
function New-ModelDeployment {
    param(
        [Parameter(Mandatory)][string]$DeploymentName,
        [Parameter(Mandatory)][string]$ModelName,
        [Parameter(Mandatory)][string]$ModelVersion,
        [int]$Capacity = 10,
        [string]$SkuName = 'GlobalStandard'
    )

    $existing = & az cognitiveservices account deployment show `
        --resource-group $ResourceGroup --name $FoundryName `
        --deployment-name $DeploymentName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Write-Status SKIP "Deployment '$DeploymentName' already exists."
        return
    }

    if ($PSCmdlet.ShouldProcess($DeploymentName, "Create model deployment ($ModelName $ModelVersion)")) {
        Write-Status WAIT "Creating '$DeploymentName' -> $ModelName ($ModelVersion, $SkuName cap $Capacity) -- 30-90s..."
        $out = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $DeploymentName `
            --model-name $ModelName `
            --model-version $ModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity $Capacity `
            --sku-name $SkuName `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Deployment '$DeploymentName' failed: $out"
            Write-Host ''
            Write-Host "Most likely cause: $ModelName $SkuName quota exhausted in $Location." -ForegroundColor Yellow
            Write-Host 'Quick remediation: request quota at https://aka.ms/oai/quotaincrease' -ForegroundColor Yellow
            Write-Host '  OR lower --sku-capacity, OR swap region (eastus2 / swedencentral also carry these models).' -ForegroundColor Yellow
            throw "Model deployment '$DeploymentName' failed."
        }
        Write-Status OK "Deployment '$DeploymentName' created."
    }
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
            Write-Status OK 'Delete submitted (async). Resources will be gone in ~5-10 min.'
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
        Invoke-Az -Args @(
            'group','create',
            '--name', $ResourceGroup,
            '--location', $Location,
            '--tags', 'purpose=ai901-lesson07-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (hosts Content Understanding GA + 3 model deployments)
# ----------------------------------------------------------------------------

Write-Section "Foundry AIServices resource: $FoundryName"

$existingAcct = & az cognitiveservices account show `
    --name $FoundryName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Foundry resource already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Create Foundry AIServices resource')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $FoundryName,
            '--resource-group', $ResourceGroup,
            '--kind', 'AIServices',
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $FoundryName,
            '--assign-identity',
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Foundry resource created.'
    }
}

# Guard data-plane queries under -WhatIf (resource does not exist yet).
$foundryNow = & az cognitiveservices account show `
    --name $FoundryName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $foundryNow) {
    Write-Status SKIP 'Foundry resource not present yet (expected under -WhatIf) -- skipping project-management check.'
    $projMgmt = 'True'
} else {
    $projMgmt = (Invoke-Az -Args @(
        'cognitiveservices','account','show',
        '--name',$FoundryName,'--resource-group',$ResourceGroup,
        '--query','properties.allowProjectManagement','-o','tsv'
    )) -join ''
}
if ($projMgmt -ne 'True') {
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Enable project management')) {
        Invoke-Az -Args @(
            'resource','update',
            '--resource-group',$ResourceGroup,
            '--name',$FoundryName,
            '--resource-type','Microsoft.CognitiveServices/accounts',
            '--set','properties.allowProjectManagement=true',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Project management enabled.'
    }
} else {
    Write-Status SKIP 'Project management already enabled.'
}

# ----------------------------------------------------------------------------
# Foundry project
# ----------------------------------------------------------------------------

Write-Section "Foundry project: $ProjectName"

$existingProj = & az cognitiveservices account project show `
    --name $FoundryName --resource-group $ResourceGroup `
    --project-name $ProjectName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingProj) {
    Write-Status SKIP 'Foundry project already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ProjectName, 'Create Foundry project')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','project','create',
            '--resource-group',$ResourceGroup,
            '--name',$FoundryName,
            '--project-name',$ProjectName,
            '--location',$Location,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Foundry project created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployments -- the GA Content Understanding contract
# ----------------------------------------------------------------------------
# Versions verified via:
#   az cognitiveservices model list --location eastus
#     gpt-4.1                 -> 2025-04-14  (GlobalStandard)
#     gpt-4.1-mini            -> 2025-04-14  (GlobalStandard)
#     text-embedding-3-large  -> 1           (GlobalStandard)

Write-Section 'Model deployments: gpt-4.1, gpt-4.1-mini, text-embedding-3-large'

New-ModelDeployment -DeploymentName $ChatDeploymentName      -ModelName 'gpt-4.1'                -ModelVersion '2025-04-14' -Capacity 10
New-ModelDeployment -DeploymentName $MiniDeploymentName      -ModelName 'gpt-4.1-mini'           -ModelVersion '2025-04-14' -Capacity 10
New-ModelDeployment -DeploymentName $EmbeddingDeploymentName -ModelName 'text-embedding-3-large' -ModelVersion '1'          -Capacity 50

# ----------------------------------------------------------------------------
# IAM: grant signed-in user "Cognitive Services User" on the Foundry resource
# ----------------------------------------------------------------------------
# Required by Content Understanding even for subscription owners -- the analyzer
# data plane and the modelDeployments config call are gated on this data-plane
# role, not on ARM ownership. Idempotent: az role assignment create is a no-op
# if the assignment already exists.

Write-Section 'IAM: Cognitive Services User on the Foundry resource'

$signedInOid  = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$foundryArmId = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','id','-o','tsv')) -join ''

if ($PSCmdlet.ShouldProcess($FoundryName, 'Grant Cognitive Services User to signed-in user')) {
    $roleOut = & az role assignment create `
        --assignee-object-id $signedInOid `
        --assignee-principal-type 'User' `
        --role 'Cognitive Services User' `
        --scope $foundryArmId `
        --output none 2>&1
    if ($LASTEXITCODE -ne 0 -and ($roleOut -notmatch 'RoleAssignmentExists')) {
        Write-Status FAIL "Role assignment failed: $roleOut"
        Write-Host 'You can still use key auth for the demo, but Studio + Entra calls may 403.' -ForegroundColor Yellow
    } else {
        Write-Status OK 'Cognitive Services User assigned (or already present).'
    }
}

# ----------------------------------------------------------------------------
# Resource-level model deployment defaults (prebuilt analyzers resolve aliases)
# ----------------------------------------------------------------------------
# GA prebuilt analyzers reference model ALIASES, not deployment names. Without
# these defaults, the first analyzer call fails with:
#   "No deployment for model 'prebuilt-analyzer-completion' was provided."
# Setting resource defaults lets every analyze request use the bare
# {"inputs":[...]} body -- which is what the Python script and web app send.
#
# Endpoint shape (per CU "bring-your-own-capacity" docs):
#   PATCH {endpoint}contentunderstanding/defaults?api-version=2025-11-01
#   { "modelDeployments": { "<alias>": "<deploymentName>", ... } }
#
# Alias map (per CU docs):
#   prebuilt-analyzer-completion       -> gpt-4.1          (invoice, receipt)
#   prebuilt-analyzer-completion-mini  -> gpt-4.1-mini     (Search analyzers)
#   prebuilt-analyzer-embedding        -> text-embedding-3-large

Write-Section 'Content Understanding: resource-level model deployment defaults'

$foundryEp  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$foundryKey = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''

$defaultsBody = @{
    modelDeployments = @{
        'prebuilt-analyzer-completion'      = $ChatDeploymentName
        'prebuilt-analyzer-completion-mini' = $MiniDeploymentName
        'prebuilt-analyzer-embedding'       = $EmbeddingDeploymentName
    }
} | ConvertTo-Json -Depth 5 -Compress

$defaultsUri = "${foundryEp}contentunderstanding/defaults?api-version=$ApiVersion"

if ($PSCmdlet.ShouldProcess($FoundryName, 'Set Content Understanding model deployment defaults')) {
    try {
        Invoke-RestMethod -Method PATCH -Uri $defaultsUri `
            -Headers @{ 'Ocp-Apim-Subscription-Key' = $foundryKey; 'Content-Type' = 'application/json' } `
            -Body $defaultsBody -ErrorAction Stop | Out-Null
        Write-Status OK 'CU model deployment defaults set (completion / completion-mini / embedding).'
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        $detail = $_.ErrorDetails.Message
        Write-Status FAIL "Defaults PATCH returned HTTP $code. Smoke test 2 will likely fail."
        if ($detail) { Write-Host "  Detail: $detail" -ForegroundColor Yellow }
        Write-Host '  Recover manually in CU Studio: https://aka.ms/cu-studio -> Settings -> Add resource -> map aliases.' -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$identityOid  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$projJson     = Invoke-Az -Args @('cognitiveservices','account','project','show','-g',$ResourceGroup,'-n',$FoundryName,'--project-name',$ProjectName,'-o','json')
$projObj      = ($projJson -join "`n") | ConvertFrom-Json
$projApi      = $projObj.properties.endpoints.'AI Foundry API'
$foundryLast4 = if ($foundryKey.Length -ge 4) { $foundryKey.Substring($foundryKey.Length - 4) } else { 'n/a' }

# ----------------------------------------------------------------------------
# Smoke test 1: chat completion against gpt-4.1 (proves deployment is live)
# ----------------------------------------------------------------------------

Write-Section 'Smoke test 1: chat completion against gpt-4.1'

$chatBody = @{
    messages = @(@{ role = 'user'; content = 'Reply with the single word OK.' })
    max_completion_tokens = 8
} | ConvertTo-Json -Compress
$chatUri = "${foundryEp}openai/deployments/$ChatDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $chatUri `
        -Headers @{ 'api-key' = $foundryKey; 'Content-Type' = 'application/json' } `
        -Body $chatBody -ErrorAction Stop
    if ($smokeObj.choices) {
        Write-Status OK "Chat smoke test passed (HTTP 200; model id: $($smokeObj.model))."
    } else {
        Write-Status FAIL "Chat smoke test response unexpected: $($smokeObj | ConvertTo-Json -Compress)"
    }
} catch {
    Write-Status FAIL "Chat smoke test threw: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# Smoke test 2: live Content Understanding prebuilt-invoice analyze (POST + poll)
# ----------------------------------------------------------------------------
# This proves the full Lesson 07 path: a prebuilt analyzer resolves its model
# alias to the gpt-4.1 deployment and returns a Succeeded result.
# Uses an official Microsoft sample invoice so there is zero local-file dependency.

Write-Section 'Smoke test 2: Content Understanding prebuilt-invoice (POST + poll)'

$sampleInvoiceUrl = 'https://github.com/Azure-Samples/azure-ai-content-understanding-python/raw/refs/heads/main/data/invoice.pdf'
$analyzeUri  = "${foundryEp}contentunderstanding/analyzers/prebuilt-invoice:analyze?api-version=$ApiVersion"
$analyzeBody = @{ inputs = @(@{ url = $sampleInvoiceUrl }) } | ConvertTo-Json -Depth 5 -Compress

# Retry up to 3 times -- resource defaults + role can take a few seconds to propagate.
$smokeSucceeded = $false
for ($attempt = 1; $attempt -le 3 -and -not $smokeSucceeded; $attempt++) {
    try {
        $resp = Invoke-WebRequest -Method POST -Uri $analyzeUri `
            -Headers @{ 'Ocp-Apim-Subscription-Key' = $foundryKey; 'Content-Type' = 'application/json' } `
            -Body $analyzeBody -ErrorAction Stop
        $opLocation = $resp.Headers['Operation-Location']
        if ($opLocation -is [array]) { $opLocation = $opLocation[0] }

        if (-not $opLocation) {
            Write-Status FAIL 'Analyze POST returned no Operation-Location header.'
            break
        }

        Write-Status WAIT "Analyze accepted (attempt $attempt) -- polling (up to ~60s)..."
        $status = 'Running'
        $tries  = 0
        $pollErr = $null
        while ($status -in @('Running','NotStarted') -and $tries -lt 30) {
            Start-Sleep -Seconds 2
            $poll = Invoke-RestMethod -Method GET -Uri $opLocation `
                -Headers @{ 'Ocp-Apim-Subscription-Key' = $foundryKey } -ErrorAction Stop
            $status  = $poll.status
            $pollErr = $poll.error
            $tries++
        }
        if ($status -eq 'Succeeded') {
            $vendor = $poll.result.contents[0].fields.VendorName.valueString
            Write-Status OK "Content Understanding analyze SUCCEEDED ($tries polls). VendorName: $vendor."
            $smokeSucceeded = $true
        } elseif ($pollErr -and ($pollErr.innererror.message -match 'No deployment for model') -and $attempt -lt 3) {
            Write-Status WAIT "Model defaults not propagated yet -- retrying in 8s (attempt $attempt of 3)..."
            Start-Sleep -Seconds 8
        } else {
            Write-Status FAIL "Analyze ended in status '$status' after $tries polls."
            if ($pollErr) { Write-Host "  Error: $($pollErr.innererror.message)" -ForegroundColor Yellow }
            break
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 403 -and $attempt -lt 3) {
            Write-Status WAIT "HTTP 403 (role propagating) -- retrying in 8s (attempt $attempt of 3)..."
            Start-Sleep -Seconds 8
        } else {
            Write-Status FAIL "CU analyze smoke test threw (HTTP $code): $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) { Write-Host "  Detail: $($_.ErrorDetails.Message)" -ForegroundColor Yellow }
            break
        }
    }
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------

Write-Section 'Deployment complete'

$result = [pscustomobject]@{
    SubscriptionName        = $acct.name
    SubscriptionId          = $acct.id
    ResourceGroup           = $ResourceGroup
    Region                  = $Location
    FoundryResource         = $FoundryName
    FoundryProject          = $ProjectName
    FoundryEndpoint         = $foundryEp
    AIFoundryApi            = $projApi
    ContentUnderstandingApi = $ApiVersion
    ChatDeployment          = "$ChatDeploymentName (gpt-4.1 2025-04-14, GlobalStandard cap 10)"
    MiniDeployment          = "$MiniDeploymentName (gpt-4.1-mini 2025-04-14, GlobalStandard cap 10)"
    EmbeddingDeployment     = "$EmbeddingDeploymentName (text-embedding-3-large v1, GlobalStandard cap 50)"
    ManagedIdentityOid      = $identityOid
    FoundryKey1Last4        = $foundryLast4
    FoundryPortalUrl        = 'https://ai.azure.com/'
    ContentUnderstandingStudio = 'https://aka.ms/cu-studio'
}

$result | Format-List

Write-Host ''
Write-Host 'NOTE on "pro mode":' -ForegroundColor Magenta
Write-Host '  Pro mode (multi-step cross-document reasoning) is preview-only' -ForegroundColor Magenta
Write-Host '  (api-version 2025-05-01-preview) and is NOT in this GA 2025-11-01' -ForegroundColor Magenta
Write-Host '  resource. Steps 1, 3, and 4 run as documented; step 2 must use standard-mode' -ForegroundColor Magenta
Write-Host '  confidence routing.' -ForegroundColor Magenta
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Populate demo/.env with the endpoint and key1 above.' -ForegroundColor Gray
Write-Host '  2. Open Content Understanding Studio: https://aka.ms/cu-studio' -ForegroundColor Gray
Write-Host '  3. Confirm the model deployment mapping under Settings -> Model deployments.' -ForegroundColor Gray
Write-Host '  4. Run the Python SDK bookend: python lesson-07-content-understanding.py' -ForegroundColor Gray
Write-Host "  5. When done: .\Deploy-Lesson07-Infrastructure.ps1 -Cleanup" -ForegroundColor Gray
Write-Host ''

return $result
