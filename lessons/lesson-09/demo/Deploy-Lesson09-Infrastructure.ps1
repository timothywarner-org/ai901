<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 9 demo --
    Prompt Engineering Fundamentals (Chat Playground + Structured Outputs + Prompt
    Shields + a Python SDK bookend).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 9 is the second half of Domain 2's portal beats. You already have a
    deployed model (L8) -- now you learn to talk to it well. Three portal beats
    (system-vs-user + few-shot, Structured Outputs with JSON Schema, jailbreak +
    Prompt Shields) then a Python SDK bookend (lesson-09-prompt-patterns.py) that
    calls the chat deployment this script provisions.

    NEW FOUNDRY, NOT CLASSIC HUB. As of mid-2026 the Microsoft Learn "deploy a model"
    flow defaults to the New Foundry toggle ON -- a project is a child resource of a
    Foundry (AIServices) resource, with NO separate Azure AI Hub. This script
    provisions the new-Foundry shape (AIServices account + project, no hub) so the
    portal UI matches the deployed resources. Map "resource" to the exam's word "hub"
    so exam-concept fidelity survives.

    Resources provisioned in rg-ai901-lesson09-demo (East US 2):

      * ai901-lesson09-foundry    -- Foundry AIServices resource (S0, kind=AIServices)
                                      with project management enabled.
                                      NOTE: this name must be globally unique -- change
                                      the default if it is already taken.
      * ai901-lesson09-project    -- Foundry project (child of the resource). Owns the
                                      deployment, the Chat Playground, and the
                                      Guardrails + controls panel the Prompt Shields
                                      demo uses.
      * gpt-4o  deployment        -- the chat model for the Playground and SDK bookend.
                                      gpt-4o 2024-11-20 is GA in East US 2 and SUPPORTS
                                      Structured Outputs (json_schema + strict), which
                                      older JSON-mode-only models do not.

    Why gpt-4o and NOT gpt-4o-mini (the L8 default):
      The Structured Outputs demo (response_format json_schema, strict:true) requires
      a model on the Structured-Outputs supported-models list. gpt-4o 2024-11-20 is
      on that list and deploys cleanly in East US 2 -- no deprecation trap (unlike L8's
      gpt-4o-mini, which is blocked for NEW deployments since 2026-03-31). Naming the
      deployment "gpt-4o" keeps the deployment name and the SDK `model=` argument
      matching the exam answer.

    Cost: < $0.50 per run. Foundry S0 + a Standard model deployment are
    pay-per-token only -- no idle charge. Run -Cleanup when you finish.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson09-demo.

.PARAMETER Location
    Primary Azure region. Default: eastus2.

.PARAMETER FoundryName
    Azure resource name for the Foundry (AIServices) account.
    Default: ai901-lesson09-foundry. Must be globally unique -- change if taken.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson09-project.

.PARAMETER ChatDeploymentName
    Name of the chat deployment. Default: gpt-4o.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson09-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson09-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Author:        Tim Warner
    Created:       2026-06-01
    Verified:      2026-06-01 against MS Learn Structured Outputs (GA api-version
                   2024-10-21; gpt-4o 2024-11-20 on the supported-models list) and the
                   az cognitiveservices model list catalog (gpt-4o 2024-11-20 =
                   GenerallyAvailable, Standard, East US 2).
    GUI fallback:  Every step is also reproducible via the Foundry portal at
                   https://ai.azure.com -- see the lesson README.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson09-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson09-foundry',      # globally unique -- change if taken

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson09-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

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
    Write-Section "Cleanup: deleting resource group $ResourceGroup"
    # L9 has no standalone kind=OpenAI account (that was an L8-only drive-by prop), so
    # there is no soft-delete name reservation to purge -- a plain RG delete is enough.
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
            '--tags', 'purpose=ai901-lesson09-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (new Foundry -- the resource that owns the project)
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
# Model deployment: gpt-4o (DEPLOYMENT NAME == MODEL NAME for this lesson)
# ----------------------------------------------------------------------------
# gpt-4o 2024-11-20 is GenerallyAvailable in East US 2 and is on the Structured
# Outputs supported-models list (verified MS Learn 2026-06-01). No deprecation trap
# here -- the deployment name, the SDK `model=` argument, and the exam answer all
# line up for this lesson.

$ChatModelName = 'gpt-4o'
$ChatModelVersion = '2024-11-20'   # GA in East US 2, Structured Outputs supported

Write-Section "Model deployment: $ChatDeploymentName -> $ChatModelName ($ChatModelVersion)"

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
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$foundryEp    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$foundryKey   = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$foundryLast4 = if ($foundryKey.Length -ge 4) { $foundryKey.Substring($foundryKey.Length - 4) } else { 'n/a' }

# ----------------------------------------------------------------------------
# Smoke test: Structured Outputs against the gpt-4o deployment
# ----------------------------------------------------------------------------
# This is the same shape the SDK bookend makes (json_schema + strict), in PowerShell --
# it proves the deployment answers AND that the deployed model honors the schema
# guarantee. A plain chat call would not catch a model that silently lacks Structured
# Outputs support; this one does.

Write-Section 'Smoke test: Structured Outputs against gpt-4o deployment'

$smokeSchema = @{
    type       = 'object'
    properties = @{ ok = @{ type = 'boolean' } }
    required   = @('ok')
    additionalProperties = $false
}
$body = @{
    messages = @(
        @{ role = 'system'; content = 'You return only JSON matching the schema.' },
        @{ role = 'user';   content = 'Set ok to true.' }
    )
    max_tokens = 20
    response_format = @{
        type = 'json_schema'
        json_schema = @{ name = 'smoke'; strict = $true; schema = $smokeSchema }
    }
} | ConvertTo-Json -Depth 10 -Compress
$uri = "${foundryEp}openai/deployments/$ChatDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $uri `
        -Headers @{ 'api-key' = $foundryKey; 'Content-Type' = 'application/json' } `
        -Body $body -ErrorAction Stop
    if ($smokeObj.choices) {
        $content = $smokeObj.choices[0].message.content
        Write-Status OK "Smoke test passed (HTTP 200; model id: $($smokeObj.model); content: $content)."
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
    ChatModel           = "$ChatModelName ($ChatModelVersion, Standard, cap 10) -- Structured Outputs capable"
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
Write-Host '  3. Follow the lesson README for the portal beats and Playground steps.' -ForegroundColor Gray
Write-Host '  4. Run the SDK bookend: pip install -r requirements.txt && python lesson-09-prompt-patterns.py' -ForegroundColor Gray
Write-Host "  5. When done: .\Deploy-Lesson09-Infrastructure.ps1 -Cleanup" -ForegroundColor Gray
Write-Host ''

return $result
