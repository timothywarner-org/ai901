<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 8 demo --
    Tour Microsoft Foundry and Deploy Your First Model (portal tour + Playground +
    Python SDK bookend).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 8 opens Domain 2. The lesson IS the Foundry portal -- hub/project navigation,
    the model catalog, the deploy wizard, and the Chat Playground. The only runnable
    code artifact is the Python SDK bookend (lesson-08-foundry-chat.py),
    which calls the chat deployment this script provisions.

    NEW FOUNDRY, NOT CLASSIC HUB. As of mid-2026 the Microsoft Learn "deploy a model"
    flow defaults to the New Foundry toggle ON -- a project is a child resource of a
    Foundry (AIServices) resource, with NO separate Azure AI Hub. The classic hub-based
    pattern moved to /azure/foundry-classic and is flagged "migrate." This script
    provisions the new-Foundry shape (AIServices account + project, no hub) so the
    portal UI matches the deployed resources and current Microsoft direction.

    Resources provisioned in rg-ai901-lesson08-demo (East US 2):

      * ai901-lesson08-foundry    -- Foundry AIServices resource (S0, kind=AIServices)
                                      with project management enabled. This is the
                                      "resource" that owns the project in New Foundry.
                                      NOTE: this name must be globally unique -- change
                                      the default if it is already taken.
      * ai901-lesson08-project    -- Foundry project (child of the resource). The
                                      project scope owns deployments, Playground,
                                      evaluations -- the LO 2.1.2 teaching point.
      * gpt-4o-mini  deployment   -- the chat model for the Playground and the SDK
                                      bookend. gpt-4o-mini is the AI-901 cost-and-
                                      capability default; LO 2.1.3 names it explicitly.
      * text-embedding-3-small    -- reference embedding deployment so the
                                      "embeddings power semantic search" teaching point
                                      has a real deployment visible in the Models panel.
      * ai901-lesson08-aoai       -- LEGACY standalone Azure OpenAI account
                                      (kind=OpenAI, its own *.openai.azure.com
                                      endpoint, ZERO deployments). Historical-context
                                      drive-by: shows "where Azure OpenAI used to live"
                                      before the New Foundry resource model.
                                      Not a runnable target; nothing calls it.
                                      NOTE: this name must be globally unique -- change
                                      the default if it is already taken.

    Cost: < $0.50 per run. Foundry S0 + Standard model deployments are
    pay-per-token only -- no idle charge. The legacy AOAI account has zero deployments,
    so it has zero inference cost. Run -Cleanup when you finish -- cleanup
    PURGES the AOAI soft-delete so its name is reusable immediately instead of being
    reserved for 48 hours.

    Model family rationale -- avoids replay across the lesson series:
      L5 = gpt-4.1-mini   (classic-vs-generative sentiment)
      L6 = gpt-4o + gpt-image-1.5  (multimodal vision + image gen)
      L7 = gpt-4.1 + gpt-4.1-mini + text-embedding-3-large (Content Understanding)
      L8 = gpt-4o-mini    (the canonical AI-901 cost/capability chat default) +
           text-embedding-3-small (the cost-tier embedding model named in LO 2.1.3)

    L8 deliberately deploys gpt-4o-mini, not gpt-4o: LO 2.1.3 teaches gpt-4o-mini as
    the "cost-effective, high-volume chat" answer, and the Playground should show
    the exact model the exam names. text-embedding-3-small is new to the series.

    IMPORTANT model note (verified 2026-05-31): NEW deployments of gpt-4o-mini
    (2024-07-18) are blocked -- the model was deprecated for new deployments on
    2026-03-31, even though AI-901 LO 2.1.3 still names gpt-4o-mini. Resolution:
    deploy the actual successor gpt-4.1-mini (GA, deployable), but NAME the
    deployment "gpt-4o-mini" so the deployment name and the SDK's `model=` argument
    still match the exam answer. This is a bonus teaching moment -- the `model`
    argument is the DEPLOYMENT name, NOT the underlying model name.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson08-demo.

.PARAMETER Location
    Primary Azure region. Default: eastus2.

.PARAMETER FoundryName
    Azure resource name for the Foundry (AIServices) account.
    Default: ai901-lesson08-foundry. Must be globally unique -- change if taken.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson08-project.

.PARAMETER ChatDeploymentName
    Name of the chat deployment used by the Playground and SDK bookend.
    Default: gpt-4o-mini.

.PARAMETER EmbeddingDeploymentName
    Name of the reference embedding deployment. Default: text-embedding-3-small.

.PARAMETER AoaiName
    Azure resource name for the legacy standalone Azure OpenAI account (kind=OpenAI,
    no deployments, historical-context drive-by).
    Default: ai901-lesson08-aoai. Must be globally unique -- change if taken.

.PARAMETER Cleanup
    Switch. Purges the legacy Azure OpenAI account, then deletes the resource group,
    then exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson08-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson08-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Author:        Tim Warner
    Created:       2026-05-31
    Verified:      2026-05-31 against MS Learn Foundry "deploy a model" (New Foundry
                   toggle ON is the documented default) + AzureOpenAI Python client
                   (api_version 2024-10-21 GA).
    GUI fallback:  Every step is also reproducible via the Foundry portal at
                   https://ai.azure.com -- see the lesson README.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson08-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson08-foundry',      # globally unique -- change if taken

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson08-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o-mini',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$EmbeddingDeploymentName = 'text-embedding-3-small',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$AoaiName = 'ai901-lesson08-aoai',            # globally unique -- change if taken

    [Parameter()]
    [switch]$Cleanup
)

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
    # Glyphs carry the meaning (not color alone) -- accessibility for colorblind reading.
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
    Write-Status FAIL "Not signed in. Run: az login"
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
    Write-Section "Cleanup: purging legacy Azure OpenAI account $AoaiName"
    # Order matters. A bare RG delete soft-deletes the kind=OpenAI account, which
    # RESERVES its name for ~48h and blocks reuse under the same name. So delete
    # it synchronously, PURGE it (frees the name now), THEN drop the RG.
    & az cognitiveservices account show --name $AoaiName --resource-group $ResourceGroup --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        if ($PSCmdlet.ShouldProcess($AoaiName, 'Delete + purge legacy Azure OpenAI account')) {
            Write-Status WAIT "Deleting $AoaiName (synchronous)..."
            Invoke-Az -Args @('cognitiveservices','account','delete','--name',$AoaiName,'--resource-group',$ResourceGroup) | Out-Null
            Write-Status WAIT "Purging soft-deleted $AoaiName (frees the name immediately)..."
            $purge = & az cognitiveservices account purge --name $AoaiName --resource-group $ResourceGroup --location $Location 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Status FAIL "Purge failed (name may stay reserved ~48h): $purge"
            } else {
                Write-Status OK 'Legacy Azure OpenAI account purged.'
            }
        }
    } else {
        Write-Status SKIP "Legacy Azure OpenAI account $AoaiName not found -- nothing to purge."
    }

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
            '--tags', 'purpose=ai901-lesson08-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (new Foundry -- the resource that owns the project)
# ----------------------------------------------------------------------------
# In New Foundry the "project" is a child of an AIServices account, NOT of an
# Azure AI Hub. Enabling allowProjectManagement on the account is what turns it
# into a Foundry resource that can own projects. No hub, no separate storage or
# key vault -- that is the whole point of the new resource model the lesson tours.

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

$projMgmt = (Invoke-Az -Args @(
    'cognitiveservices','account','show',
    '--name',$FoundryName,'--resource-group',$ResourceGroup,
    '--query','properties.allowProjectManagement','-o','tsv'
)) -join ''
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
        Write-Status OK 'Project management enabled (this is what makes it a Foundry resource).'
    }
} else {
    Write-Status SKIP 'Project management already enabled.'
}

# ----------------------------------------------------------------------------
# Foundry project (child of the resource -- new Foundry shape)
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
# Model deployment: gpt-4o-mini (DEPLOYMENT NAME) -> gpt-4.1-mini (MODEL)
# ----------------------------------------------------------------------------
# IMPORTANT real-world note (verified 2026-05-31): NEW deployments of
# gpt-4o-mini (2024-07-18) are blocked -- the model was deprecated for new
# deployments on 2026-03-31 (ServiceModelDeprecated), even though AI-901 LO
# 2.1.3 still names gpt-4o-mini as the cost/capability answer.
#
# Resolution: deploy the actual successor, gpt-4.1-mini (GA, deployable), but
# NAME the deployment "gpt-4o-mini" so the deployment name and the SDK's
# `model=` argument still match the exam answer. This is a bonus teaching
# moment -- the `model` argument is the DEPLOYMENT name, NOT the underlying
# model name, which is the single most-tested Python detail on this exam.

$ChatModelName = 'gpt-4.1-mini'      # underlying model actually deployed
$ChatModelVersion = '2025-04-14'      # GA in eastus2

Write-Section "Model deployment: $ChatDeploymentName (deployment) -> $ChatModelName (model)"

$existingChat = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ChatDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingChat) {
    Write-Status SKIP 'Chat deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ChatDeploymentName, "Create $ChatModelName chat deployment")) {
        Write-Status WAIT "Creating $ChatDeploymentName -> $ChatModelName (this can take 30-90s)..."
        $deployOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ChatDeploymentName `
            --model-name $ChatModelName `
            --model-version $ChatModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity 10 `
            --sku-name 'Standard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Chat deployment failed: $deployOutput"
            Write-Host ''
            Write-Host "Most likely cause: $ChatModelName Standard quota exhausted in this region." -ForegroundColor Yellow
            Write-Host 'Quick remediation: request quota at https://aka.ms/oai/quotaincrease' -ForegroundColor Yellow
            Write-Host '  OR swap to GlobalStandard -- change --sku-name above.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat deployment created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: text-embedding-3-small (reference -- semantic search point)
# ----------------------------------------------------------------------------

Write-Section "Model deployment: $EmbeddingDeploymentName -> text-embedding-3-small"

$existingEmbed = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $EmbeddingDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingEmbed) {
    Write-Status SKIP 'Embedding deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($EmbeddingDeploymentName, 'Create text-embedding-3-small deployment')) {
        Write-Status WAIT "Creating $EmbeddingDeploymentName (this can take 30-90s)..."
        $embedOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $EmbeddingDeploymentName `
            --model-name 'text-embedding-3-small' `
            --model-version '1' `
            --model-format 'OpenAI' `
            --sku-capacity 30 `
            --sku-name 'Standard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            # Non-fatal: the embedding model is only a reference talking point. The chat
            # deployment is what the SDK bookend actually calls.
            Write-Status FAIL "Embedding deployment failed (non-blocking): $embedOutput"
            Write-Host 'The embedding deployment is a reference talking point only -- the demo still runs without it.' -ForegroundColor Yellow
        } else {
            Write-Status OK 'Embedding deployment created.'
        }
    }
}

# ----------------------------------------------------------------------------
# Legacy standalone Azure OpenAI account (historical-context drive-by, NO deployments)
# ----------------------------------------------------------------------------
# The classic pre-Foundry resource: Microsoft.CognitiveServices/accounts with
# kind=OpenAI and its own *.openai.azure.com endpoint. It exists purely to contrast
# "where Azure OpenAI used to live" against the New Foundry resource above.
# Intentionally has ZERO model deployments -- a tour stop, not a runnable target.

Write-Section "Legacy Azure OpenAI account: $AoaiName (historical context, no deployments)"

$existingAoai = & az cognitiveservices account show `
    --name $AoaiName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAoai) {
    Write-Status SKIP 'Legacy Azure OpenAI account already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($AoaiName, 'Create legacy Azure OpenAI account (kind=OpenAI)')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $AoaiName,
            '--resource-group', $ResourceGroup,
            '--kind', 'OpenAI',
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $AoaiName,
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Legacy Azure OpenAI account created (no deployments -- drive-by only).'
    }
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$foundryEp    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$foundryKey   = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$foundryLast4 = if ($foundryKey.Length -ge 4) { $foundryKey.Substring($foundryKey.Length - 4) } else { 'n/a' }
$aoaiEp = (& az cognitiveservices account show -g $ResourceGroup -n $AoaiName --query properties.endpoint -o tsv 2>$null) -join ''
if (-not $aoaiEp) { $aoaiEp = '(not provisioned)' }

# ----------------------------------------------------------------------------
# Smoke test: chat completion against the gpt-4o-mini deployment
# ----------------------------------------------------------------------------

Write-Section 'Smoke test: chat completion against gpt-4o-mini deployment'

$body = @{
    messages = @(@{ role = 'user'; content = 'Reply with the single word OK.' })
    max_tokens = 8
} | ConvertTo-Json -Compress
$uri = "${foundryEp}openai/deployments/$ChatDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $uri `
        -Headers @{ 'api-key' = $foundryKey; 'Content-Type' = 'application/json' } `
        -Body $body -ErrorAction Stop
    if ($smokeObj.choices) {
        Write-Status OK "Smoke test passed (HTTP 200; model id: $($smokeObj.model))."
    } else {
        Write-Status FAIL "Smoke test response unexpected: $($smokeObj | ConvertTo-Json -Compress)"
    }
} catch {
    Write-Status FAIL "Smoke test threw: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------

Write-Section 'Deployment complete'

$result = [pscustomobject]@{
    SubscriptionId      = $acct.id
    TenantId            = $acct.tenantId
    ResourceGroup       = $ResourceGroup
    Region              = $Location
    FoundryResource     = $FoundryName
    FoundryProject      = $ProjectName
    FoundryEndpoint     = $foundryEp
    ChatDeployment      = $ChatDeploymentName
    ChatModel           = "$ChatModelName ($ChatModelVersion, Standard, cap 10) -- deployment named '$ChatDeploymentName' to match exam answer"
    EmbeddingDeployment = $EmbeddingDeploymentName
    EmbeddingModel      = 'text-embedding-3-small (v1, Standard, cap 30)'
    LegacyAoaiResource  = "$AoaiName (kind=OpenAI, 0 deployments -- historical-context drive-by)"
    LegacyAoaiEndpoint  = $aoaiEp
    ManagedIdentityOid  = $identityOid
    FoundryKey1Last4    = $foundryLast4
    PortalUrl           = "https://portal.azure.com/#@$($acct.tenantId)/resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/overview"
    FoundryPortalUrl    = 'https://ai.azure.com/'
}

$result | Format-List

Write-Host ''
Write-Host 'Paste into .env (see .env.example):' -ForegroundColor Cyan
Write-Host "  AZURE_OPENAI_ENDPOINT=$foundryEp" -ForegroundColor Gray
Write-Host "  AZURE_OPENAI_KEY=<run: az cognitiveservices account keys list -g $ResourceGroup -n $FoundryName --query key1 -o tsv>" -ForegroundColor Gray
Write-Host "  AZURE_OPENAI_CHAT_DEPLOYMENT=$ChatDeploymentName" -ForegroundColor Gray
Write-Host "  AZURE_OPENAI_API_VERSION=2024-10-21" -ForegroundColor Gray
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Open the Foundry portal at https://ai.azure.com/ -- New Foundry toggle ON.' -ForegroundColor Gray
Write-Host "  2. Switch to project: $ProjectName (under resource $FoundryName)." -ForegroundColor Gray
Write-Host '  3. Follow the lesson README for the portal tour and Playground steps.' -ForegroundColor Gray
Write-Host '  4. Run the SDK bookend: pip install -r requirements.txt && python lesson-08-foundry-chat.py' -ForegroundColor Gray
Write-Host "  5. When done: .\Deploy-Lesson08-Infrastructure.ps1 -Cleanup" -ForegroundColor Gray
Write-Host ''

return $result
